/* Bubble sort test workload reporting result via MMIO. */
#define MMIO_RESULT (*(volatile int *)0x10000000)
#define MMIO_DONE   (*(volatile int *)0x10000004)

int main(void)
{
    int swapped;
    int n, j;
    int arr[3];

    /* element by element: an initializer list may be copied from .rodata,
       which needs relocations (F3) */
    arr[0] = 6;
    arr[1] = 3;
    arr[2] = 9;
    n = 3;

    do {
        swapped = 0;
        for (j = 0; j < n - 1; j++) {
            if (arr[j] > arr[j + 1]) {
                int temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
                swapped = 1;
            }
        }
        n = n - 1;
    } while (swapped == 1);

    MMIO_RESULT = arr[0];
    MMIO_DONE = 1;
    for (;;)
        ;
}
