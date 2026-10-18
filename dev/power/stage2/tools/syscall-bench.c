// SPDX-License-Identifier: GPL-3.0-only
/*
 * Copyright (C) 2026 George Dobreff ("Witcher") and contributors
 *
 * Times a cheap system call (getppid) in a loop: the cost of entering and leaving the kernel,
 * which kernel auditing adds to (Stage 2 S3). Prints nanoseconds per call for each run.
 * Usage: syscall-bench [CALLS] [RUNS]   (run it pinned: taskset -c CPU syscall-bench)
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	long calls = argc > 1 ? atol(argv[1]) : 20000000;
	int runs = argc > 2 ? atoi(argv[2]) : 5;

	/* A short warm-up, so the clock has ramped up before the first timed run */
	for (long i = 0; i < calls / 10; i++)
		syscall(SYS_getppid);

	for (int r = 0; r < runs; r++) {
		struct timespec a, b;

		clock_gettime(CLOCK_MONOTONIC, &a);
		for (long i = 0; i < calls; i++)
			syscall(SYS_getppid);
		clock_gettime(CLOCK_MONOTONIC, &b);
		printf("%.2f\n", ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / calls);
	}
	return 0;
}
