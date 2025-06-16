#define _GNU_SOURCE
#include "logic.h"
#include "parser.tab.h"
#include <stdio.h>

extern int yyparse(void);
extern FILE *yyin;

int from_file = 0;

int main(int argc, char **argv)
{
    logic_init();
    puts("Logic");
    puts("");

    if(argc > 2){
        fprintf(stderr, "Usage: %s [file]\n", argv[0]);
        return 1;
    }

    if(argc == 2){
        yyin = fopen(argv[1], "r");
        if(!yyin){
            perror(argv[1]);
            return 1;
        }
        from_file = 1;
    }

    yyparse();

    if(from_file)
        fclose(yyin);

    return 0;
}