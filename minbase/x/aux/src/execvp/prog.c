/* execvp: simple (or sophisticated?) launcher
 *
 * SPDX-License-Identifier: BSD-3-Clause
 * (c) 2022, Konstantin Demin
 *
 * Example usage in shell scripts:
 *   /x/bin/execvp program /tmp/list
 * is roughly equal to:
 *   ( sleep 5 ; [ -w /tmp/list ] && rm -f /tmp/list ; ) &
 *   xargs -0 -r -a /tmp/list program
 * where /tmp/list is file with NUL-separated arguments
 * except:
 * - execvp is NOT replacement for xargs
 * - execvp's return code is exact program return code
 *   or appropriate error code
 * - there's no need to sleep()
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <sys/stat.h>

#define CMD_LEN_MAX 2097151
#define CMD_ARGS_MAX 4095

static char   n_buf[CMD_LEN_MAX + 1];
static int    n_argc = 0;
static char * n_argv[CMD_ARGS_MAX + 1];

static char   e_buf[8192];
static char * e_str = NULL;

static void usage(void)
{
	fprintf(stderr,
		"Usage: execvp <program> <script>\n"
		"  <script> - file with NUL-separated arguments\n"
		"Attention: <script> file will be DELETED if it has 'u+w' permission\n"
	);
}

int main(int argc, char * argv[])
{
	int n_ret = 0;
	int b_del = 0;

	if (argc == 1) {
		usage();
		return 0;
	}

	if (argc != 3) {
		usage();
		return EAGAIN;
	}

	memset(&e_buf, 0, sizeof(e_buf));

	int f_fd = open(argv[2], O_RDONLY | O_NOFOLLOW);
	if (f_fd < 0) {
		n_ret = errno;
		e_str = strerror_r(n_ret, e_buf, sizeof(e_buf));
		fprintf(stderr, "open(2) error %d \"%s\", file %s\n", n_ret, e_str, argv[2]);
		goto cleanup;
	}

	struct stat f_stat;
	memset(&f_stat, 0, sizeof(f_stat));
	if (fstat(f_fd, &f_stat) < 0) {
		n_ret = errno;
		e_str = strerror_r(n_ret, e_buf, sizeof(e_buf));
		fprintf(stderr, "fstat(2) error %d \"%s\", file %s\n", n_ret, e_str, argv[2]);
		goto cleanup;
	}

	b_del = (f_stat.st_mode & S_IWUSR) != 0;

	if (f_stat.st_size > CMD_LEN_MAX) {
		fprintf(stderr, "argument error: file is too big (stat.st_size=%ld): %s\n", f_stat.st_size, argv[2]);
		goto cleanup;
	}

	memset(n_argv, 0, sizeof(n_argv));
	n_argv[0] = argv[1];

	if (f_stat.st_size != 0) {
		memset(&n_buf, 0, sizeof(n_buf));
		if (f_stat.st_size != read(f_fd, n_buf, f_stat.st_size)) {
			n_ret = errno;
			e_str = strerror_r(n_ret, e_buf, sizeof(e_buf));
			fprintf(stderr, "read(2) error %d: %s\n", n_ret, e_str);
			goto cleanup;
		}

		off_t i = 0;
		char * t = n_buf;
		for (i = 0; i < f_stat.st_size; i++) {
			if (n_buf[i]) {
				continue;
			}

			n_argc++;
			if (n_argc == CMD_ARGS_MAX) {
				n_ret = E2BIG;
				fprintf(stderr, "arg count reached limit (%d)\n", CMD_ARGS_MAX);
				goto cleanup;
			}
			n_argv[n_argc] = t;
			t = &n_buf[i + 1];
		}
	}

	close(f_fd); f_fd = -1;

	if (b_del) {
		unlink(argv[2]);
		b_del = 0;
	}

	execvp(n_argv[0], n_argv);
	// execution follows here in case of errors
	n_ret = errno;
	e_str = strerror_r(n_ret, e_buf, sizeof(e_buf));
	fprintf(stderr, "execvp(3) error %d: %s\n", n_ret, e_str);
	return n_ret;

cleanup:
	if (f_fd >= 0) {
		close(f_fd);
	}

	if (b_del) {
		unlink(argv[2]);
	}

	return n_ret;
}
