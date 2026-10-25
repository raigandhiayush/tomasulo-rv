/* RV32M factorial workload computing 7! via dependent MUL instructions. */
#define MMIO_RESULT (*(volatile int *)0x10000000)
#define MMIO_DONE   (*(volatile int *)0x10000004)

int main(void)
{
    int f = 1;
    int i;

    for (i = 2; i <= 7; i++)
        f = f * i;

    MMIO_RESULT = f;
    MMIO_DONE = 1;
    for (;;)
        ;
}
