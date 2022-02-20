/* execvp: simple (or sophisticated?) launcher
 *
 * SPDX-License-Identifier: BSD-3-Clause
 * (c) 2022, Konstantin Demin
 *
 * Example usage in shell scripts:
 *   /x/bin/execvp program /tmp/list
 * is roughly equal to:
 *   ( sleep 5 ; rm -f /tmp/list ; ) &
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

#define CMD_LEN_MAX 1048576
#define CMD_ARGS_MAX 2047

int n_argc = 0;
char * n_argv[CMD_ARGS_MAX + 1];

char n_buf[CMD_LEN_MAX];

char e_buf[4096];

void usage(void)
{
	fprintf(stderr,
		"Usage: execvp <program> <script>\n"
		"  <script> - file with NUL-separated arguments\n"
		"Attention: <script> will be deleted in almost any case!\n"
	);
}

int main(int argc, char * argv[])
{
	int    n_ret = 0;
	int     f_fd = -1;
	char * e_str = NULL;
	struct stat f_stat;

	if (argc == 1) {
		usage();
		return 0;
	}

	if (argc != 3) {
		usage();
		return EINVAL;
	}

	memset(&e_buf, 0, sizeof(e_buf));

	f_fd = open(argv[2], O_RDONLY | O_NOFOLLOW);
	if (f_fd < 0) {
		n_ret = errno;
		e_str = strerror_r(n_ret, e_buf, sizeof(e_buf));
		fprintf(stderr, "open(2) error %d: %s\n", n_ret, e_str);
		goto cleanup;
	}

	memset(&f_stat, 0, sizeof(f_stat));
	if (fstat(f_fd, &f_stat) < 0) {
		n_ret = errno;
		e_str = strerror_r(n_ret, e_buf, sizeof(e_buf));
		fprintf(stderr, "fstat(2) error %d: %s\n", n_ret, e_str);
		goto cleanup;
	}

	if ((f_stat.st_size < 0) || (f_stat.st_size > CMD_LEN_MAX)) {
		n_ret = ENOENT;
		fprintf(stderr, "%s stat.st_size=%ld\n", argv[2], f_stat.st_size);
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
				fprintf(stderr, "arg count reached limit: %d\n", n_argc);
				n_ret = E2BIG;
				goto cleanup;
			}
			n_argv[n_argc] = t;
			t = &n_buf[i + 1];
		}
	}

	close(f_fd);
	unlink(argv[2]);

	execvp(argv[1], n_argv);
	// execution follows here in case of errors
	n_ret = errno;
	e_str = strerror_r(n_ret, e_buf, sizeof(e_buf));
	fprintf(stderr, "execvp(3) error %d: %s\n", n_ret, e_str);
	fprintf(stderr, "argv[1]=%s\n", argv[1]);
	return n_ret;

cleanup:
	if (f_fd >= 0) {
		close(f_fd);
	}

	unlink(argv[2]);

	return n_ret;
}
