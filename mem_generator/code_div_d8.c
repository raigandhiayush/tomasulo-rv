/* RV32M divide and remainder test workload reporting result via MMIO. */
#define MMIO_RESULT (*(volatile int *)0x10000000)
#define MMIO_DONE   (*(volatile int *)0x10000004)

int main(void)
{
    int n = 12345;
    int ten = 10;
    int sum = 0;
    int a = -100;
    int b = 7;
    int q, r;

    while (n != 0) {
        sum = sum + n % ten;
        n = n / ten;
    }
    q = a / b;
    r = a % b;

    MMIO_RESULT = sum * 1000 - q * 10 - r;
    MMIO_DONE = 1;
    for (;;)
        ;
}
