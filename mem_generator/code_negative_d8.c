/* Subtraction test workload reporting result via MMIO. */
#define MMIO_RESULT (*(volatile int *)0x10000000)
#define MMIO_DONE   (*(volatile int *)0x10000004)

int main(void)
{
    int a = 4;
    int b = 50;
    int c = a - b;

    MMIO_RESULT = c;
    MMIO_DONE = 1;
    for (;;)
        ;
}
