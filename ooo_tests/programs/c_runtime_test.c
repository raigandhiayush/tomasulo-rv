/* c_runtime_test.c - exercises what the linked C flow (tools/c_to_board.sh with
 * mem_generator/runtime) adds over the old instruction-only flow: a string constant
 * (.rodata), an initialized global (.data), a global that must start at zero (.bss),
 * a struct copied from a global, recursion (stack), signed division and tinyio.h.
 * tb_uart_loader loads it through the boot loader and expects exactly:
 *   "C runtime OK\r\n" "sum=225\r\n" "neg=-32\r\n" "hex=00c0ffee\r\n", result = 0xE1, done.
 * Rebuild the test files after a change: tools/build_c_runtime_test.sh
 */
#include "board.h"
#include "tinyio.h"

static const char greeting[] = "C runtime OK\r\n";
int table[8] = {3, 1, 4, 1, 5, 9, 2, 6};    /* .data */
int zeros[16];                              /* .bss: starts at 0 */
struct pt { int x, y, z; };
struct pt origin = {7, -8, 9};

static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

int main(void)
{
    int i, s = 0;
    struct pt p = origin;                   /* struct copy */

    io_puts(greeting);
    for (i = 0; i < 8; i++) s += table[i] * (i + 1);    /* 162 */
    for (i = 0; i < 16; i++) s += zeros[i];             /* + 0 */
    s += fib(10);                                       /* + 55 = 217 */
    s += p.x + p.y + p.z;                               /* + 8 = 225 */
    io_puts("sum="); io_print_int(s);      io_puts("\r\n");
    io_puts("neg="); io_print_int(-s / 7); io_puts("\r\n");   /* -32 (C truncates) */
    io_puts("hex="); io_print_hex(0xC0FFEE); io_puts("\r\n");
    zeros[0] = 1;                           /* crt0 clears .bss again on a re-run */
    MMIO_RESULT = s;                        /* 225 = 0xE1 */
    return 0;                               /* crt0 then sets done */
}
