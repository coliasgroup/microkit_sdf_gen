#include <stdio.h>
#include <assert.h>

int var_one;

int main() {
    printf("var_one: %d\n", var_one);
    assert(var_one == 1);
}
