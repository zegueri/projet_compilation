%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "logic.h"

int yyerror(const char *s);
extern int yylex(void);

extern char *yytext;
extern int line_num;



/* ---------- structures et helpers ---------- */
enum NType { N_CONST, N_VAR, N_NOT,
               N_AND, N_OR, N_XOR, N_IMPL,
               N_FUNCALL };

struct ArgList {
    struct Node **items;
    int count;
};

static struct ArgList *alist_new(struct Node *n){
    struct ArgList *a = malloc(sizeof(*a));
    a->items = malloc(sizeof(struct Node*));
    a->items[0] = n;
    a->count = 1;
    return a;
}

static struct ArgList *alist_add(struct ArgList *a, struct Node *n){
    a->items = realloc(a->items, sizeof(struct Node*)*(a->count+1));
    a->items[a->count++] = n;
    return a;
}

struct Node {
    enum NType type;
    int   val;        /* pour N_CONST */
    int   vidx;       /* pour N_VAR   */
    struct Node *l,*r;
    char *fname;          /* pour N_FUNCALL */
    struct Node **args;   /* array of arguments */
    int   argc;
};

/* fabrique de nœuds */
struct Node *mk_const(int v){ struct Node*n=calloc(1,sizeof(*n)); n->type=N_CONST; n->val=v; return n; }
struct Node *mk_var(int id){ struct Node*n=calloc(1,sizeof(*n)); n->type=N_VAR;   n->vidx=id; return n; }
struct Node *mk_un (enum NType t,struct Node*a){ struct Node*n=calloc(1,sizeof(*n)); n->type=t; n->l=a;        return n; }
struct Node *mk_bin(enum NType t, struct Node*a,struct Node*b){ struct Node*n=calloc(1,sizeof(*n)); n->type=t; n->l=a; n->r=b; return n; }
struct Node *mk_funcall(char *name, struct Node **args, int argc){ struct Node*n=calloc(1,sizeof(*n)); n->type=N_FUNCALL; n->fname=name; n->args=args; n->argc=argc; return n; }

static int eval_node(const struct Node*n,const int*vals){
    switch(n->type){
        case N_CONST: return n->val;
        case N_VAR:   return vals[n->vidx];
        case N_NOT:   return !eval_node(n->l,vals);
        case N_AND:   return eval_node(n->l,vals)&eval_node(n->r,vals);
        case N_OR:    return eval_node(n->l,vals)|eval_node(n->r,vals);
        case N_XOR:   return eval_node(n->l,vals)^eval_node(n->r,vals);
        case N_IMPL:  return (!eval_node(n->l,vals))|eval_node(n->r,vals);
        case N_FUNCALL: {
            const Function *f = get_function(n->fname);
            if(!f){ fprintf(stderr,"Unknown function %s\n", n->fname); return 0; }
            if(n->argc != f->arity){
                fprintf(stderr,"call %s: expected %d args, got %d\n", n->fname, f->arity, n->argc);
                return 0;
            }
            int tmp[MAX_VARS];
            for(int i=0;i<n->argc;i++) tmp[i]=eval_node(n->args[i],vals);
            return eval_function(f,tmp);
        }
    }
    return 0;
}
void free_node(struct Node*n){
    if(!n) return;
    if(n->type==N_FUNCALL){
        for(int i=0;i<n->argc;i++) free_node(n->args[i]);
        free(n->args);
        free(n->fname);
    }else{
        free_node(n->l);
        free_node(n->r);
    }
    free(n);
}

/* ---------- buffers ---------- */
static unsigned char boolbuf[256];   /* tables brutes */
static int  bool_count = 0;

static char varnames[MAX_VARS][MAX_NAME];
static int  varcnt = 0;
static int  explicit_varlist = 0;
static const char *default_names[MAX_VARS] = {"x","y","z","s","t","u","v","w"};

static int  vals[8];  /* pour eval */
static int  valcnt2 = 0;

static int node_prec(enum NType t){
    switch(t){
        case N_IMPL: return 1;
        case N_OR:   return 2;
        case N_XOR:  return 3;
        case N_AND:  return 4;
        case N_NOT:  return 5;
        default:     return 6;
    }
}

static char* node_to_string_rec(const struct Node*n,int parent_prec){
    char*res=NULL; char*tmp1,*tmp2;
    switch(n->type){
        case N_CONST:
            asprintf(&res, "%d", n->val); break;
        case N_VAR:
            asprintf(&res, "%s", varnames[n->vidx]); break;
        case N_NOT:
            tmp1=node_to_string_rec(n->l,node_prec(N_NOT));
            asprintf(&res, "!%s", tmp1);
            free(tmp1); break;
        case N_AND:
        case N_OR:
        case N_XOR:
        case N_IMPL:
            tmp1=node_to_string_rec(n->l,node_prec(n->type));
            tmp2=node_to_string_rec(n->r,node_prec(n->type)+1);
            const char*op=(n->type==N_AND?"and":n->type==N_OR?"or":n->type==N_XOR?"xor":"=>");
            asprintf(&res, "%s %s %s", tmp1, op, tmp2);
            free(tmp1); free(tmp2); break;
        case N_FUNCALL:{
            asprintf(&res, "%s(", n->fname);
            for(int i=0;i<n->argc;i++){
                char *arg=node_to_string_rec(n->args[i],0);
                char *tmp;
                if(i==0)
                    asprintf(&tmp, "%s%s", res, arg);
                else
                    asprintf(&tmp, "%s, %s", res, arg);
                free(res); res=tmp; free(arg);
            }
            char *tmp;
            asprintf(&tmp, "%s)", res);
            free(res); res=tmp;
            break;}
    }
    if(node_prec(n->type)<parent_prec){ char*tmp=res; asprintf(&res,"(%s)",tmp); free(tmp); }
    return res;
}

static char* node_to_string(const struct Node*n){ return node_to_string_rec(n,0); }

static int get_var_index(const char*name){
    for(int i=0;i<varcnt;++i)
        if(!strcmp(name,varnames[i])) return i;
    if(!explicit_varlist){
        for(int i=0;i<MAX_VARS;++i){
            if(!strcmp(name, default_names[i])){
                if(i >= MAX_VARS){
                    fprintf(stderr,"Trop de variables (max %d)\n",MAX_VARS);
                    return 0;
                }
                for(int j=varcnt; j<=i && j<MAX_VARS; ++j){
                    strncpy(varnames[j], default_names[j], MAX_NAME-1);
                    varnames[j][MAX_NAME-1]='\0';
                }
                if(i >= varcnt) varcnt = i+1;
                return i;
            }
        }
    }
    if(varcnt>=MAX_VARS){
        fprintf(stderr,"Trop de variables (max %d)\n",MAX_VARS);
        return 0;
    }
    strncpy(varnames[varcnt],name,MAX_NAME-1);
    varnames[varcnt][MAX_NAME-1]='\0';
    return varcnt++;
}
%}

%union {
    int   num;
    char *str;
    struct Node *node;
    struct ArgList *alist;
}

%token <num> BOOL
%token <str> IDENT
%token NEWLINE LPAREN RPAREN LBRACE RBRACE COMMA SEMICOLON
%token KW_DEFINE KW_EVAL KW_TABLE KW_LIST KW_VARLIST KW_FORMULA KW_AT
%token KW_AND KW_OR KW_XOR KW_NOT
%token AND OR XOR NOT EQUAL IMPL

%type <node> expr
%type <alist> expr_list

%right IMPL
%left  OR KW_OR
%left  XOR KW_XOR
%left  AND KW_AND
%right NOT KW_NOT '!'

%%  /* ---------- grammaire ---------- */

input:                /* vide */ | input line ;

line:  command NEWLINE
     | NEWLINE
     | error NEWLINE  { yyerrok; yyclearin; fprintf(stderr, "Recovering to next command...\n"); }
     ;

command:
      KW_LIST                                { list_functions(); }
    | define_cmd
    | KW_TABLE   IDENT                       { print_table($2);     free($2); }
      | KW_VARLIST IDENT                       { print_varlist($2);   free($2); }
      | KW_FORMULA IDENT                       { print_formula($2);   free($2); }
      | KW_EVAL    IDENT KW_AT value_seq       { eval_and_print($2,vals,valcnt2); free($2); }
      ;

/* ----- define ----- */
define_cmd:

      KW_DEFINE IDENT opt_varlist EQUAL table_def
        {
          if (varcnt > 0)
              add_function_table($2, varcnt, varnames, boolbuf, bool_count, NULL);
          else
              add_function_table($2, -1, NULL, boolbuf, bool_count, NULL);
          free($2);
        }
    | KW_DEFINE IDENT opt_varlist EQUAL expr
        {
          int arity = varcnt;
          int size  = 1 << arity;
          unsigned char tbl[1<<MAX_VARS];
          for(int idx=0; idx<size; ++idx){
              int v[MAX_VARS];
              for(int i=0;i<arity;++i)
                  v[i] = (idx >> (arity-1-i)) & 1;
              tbl[idx] = eval_node($5,v);
          }
           char *form = node_to_string($5);
           add_function_table($2,arity,varnames,tbl,size,form);
           free(form);
           free_node($5); free($2);
        }
    ;

/* ----- liste optionnelle de variables ----- */
opt_varlist:
      /* vide */                { varcnt = 0; explicit_varlist = 0; }
    | LPAREN { explicit_varlist = 1; } id_list RPAREN
    ;

id_list:
      IDENT                    { varcnt=0; get_var_index($1); free($1); }
    | id_list COMMA IDENT      {           get_var_index($3); free($3); }
    ;

/* ----- table brute ----- */
table_def: LBRACE table_values RBRACE ;

table_values:
      BOOL               { bool_count=0; boolbuf[bool_count++]=(unsigned char)$1; }
    | table_values BOOL  { boolbuf[bool_count++]=(unsigned char)$2; }
    ;

/* ----- valeurs pour eval ----- */
value_seq:
      BOOL            { valcnt2=0; vals[valcnt2++]=$1; }
    | value_seq BOOL  {           vals[valcnt2++]=$2; }
    ;

/* ----- liste d'expressions ----- */
expr_list:
      expr                  { $$ = alist_new($1); }
    | expr_list COMMA expr  { $$ = alist_add($1,$3); }
    ;

/* ----- expressions booléennes ----- */
expr:
      expr IMPL expr            { $$ = mk_bin(N_IMPL,$1,$3); }
    | expr OR expr              { $$ = mk_bin(N_OR,$1,$3); }
    | expr KW_OR expr           { $$ = mk_bin(N_OR,$1,$3); }
    | expr XOR expr             { $$ = mk_bin(N_XOR,$1,$3); }
    | expr KW_XOR expr          { $$ = mk_bin(N_XOR,$1,$3); }
    | expr AND expr             { $$ = mk_bin(N_AND,$1,$3); }
    | expr KW_AND expr          { $$ = mk_bin(N_AND,$1,$3); }
    | NOT expr                  { $$ = mk_un (N_NOT,$2);    }
    | KW_NOT expr               { $$ = mk_un (N_NOT,$2);    }
    | LPAREN expr RPAREN        { $$ = $2; }
    | IDENT LPAREN RPAREN       { $$ = mk_funcall($1,NULL,0); }
    | IDENT LPAREN expr_list RPAREN { $$ = mk_funcall($1,$3->items,$3->count); free($3); }
    | IDENT                     { $$ = mk_var(get_var_index($1)); free($1); }
    | BOOL                      { $$ = mk_const($1); }
    ;
%%

int yyerror(const char *s){

    fprintf(stderr, "Parse error on line %d near '%s': %s\n", line_num, yytext, s);

    return 0;
}
