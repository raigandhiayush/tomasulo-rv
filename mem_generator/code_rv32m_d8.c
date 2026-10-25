/* RV32M test workload verifying MUL, MULH, MULHU, DIV, REM, DIVU, and REMU. */
#define MMIO_RESULT (*(volatile int *)0x10000000)
#define MMIO_DONE   (*(volatile int *)0x10000004)

int main(void)
{
    int a = 0x7FFFFFF0;
    int b = -0x10003;
    unsigned int ua = 0xF0000000u;
    unsigned int ub = 0x89ABCDEFu;
    unsigned int uc = 7;
    int mask = 0;

    if ((unsigned int)a * (unsigned int)b == 0x80100030u)
        mask = mask | 0x01;
    if ((int)(((long long)a * (long long)b) >> 32) == (int)0xFFFF7FFEu)
        mask = mask | 0x02;
    if ((unsigned int)(((unsigned long long)ua * (unsigned long long)ub) >> 32) == 0x81111110u)
        mask = mask | 0x04;
    if (a / b == -32766)
        mask = mask | 0x08;
    if (a % b == 32758)
        mask = mask | 0x10;
    if (ua / uc == 0x22492492u)
        mask = mask | 0x20;
    if (ua % uc == 2u)
        mask = mask | 0x40;

    MMIO_RESULT = mask;
    MMIO_DONE = 1;
    for (;;)
        ;
}
