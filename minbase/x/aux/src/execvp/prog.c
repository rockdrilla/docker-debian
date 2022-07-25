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
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <sys/stat.h>

const off_t max_script_length = 1073807360; // 1 GiB + 64 KiB

static void usage(void)
{
	fprintf(stderr,
		"Usage: execvp <program> [..<args>] <script>\n"
		"  <script> - file with NUL-separated arguments\n"
		"Attention: <script> file will be DELETED if it has 'u+w' permission\n"
	);
}

static void dump_error(int error_num, const char * where);
static void dump_path_error(int error_num, const char * where, const char * name);

int main(int argc, char * argv[])
{
	int n_ret = 0;
	int b_del = 0;

	if (argc == 1) {
		usage();
		return 0;
	}

	// skip 1st argument
	argc--; argv++;

	if (argc < 2) {
		usage();
		return EAGAIN;
	}

	char * program = argv[0];
	// skip argument
	argc--; argv++;

	char * script = argv[argc - 1];
	// trim argument
	argc--;

	int f_fd = open(script, O_RDONLY | O_NOFOLLOW);
	if (f_fd < 0) {
		dump_path_error(errno, "open(2)", script);
		goto cleanup;
	}

	struct stat f_stat;
	memset(&f_stat, 0, sizeof(f_stat));
	if (fstat(f_fd, &f_stat) < 0) {
		dump_path_error(errno, "fstat(2)", script);
		goto cleanup;
	}

	b_del = (f_stat.st_mode & S_IWUSR) != 0;

	if (f_stat.st_size > max_script_length) {
		fprintf(stderr, "argument error: file is too big (stat.st_size=%ld): %s\n", f_stat.st_size, script);
		goto cleanup;
	}

	int n_argc_base = 1 /* program */ + argc;
	int n_argc = n_argc_base;

	char * n_buf = NULL;

	if (f_stat.st_size != 0) {
		n_buf = malloc(f_stat.st_size);
		if (n_buf == NULL) {
			dump_error(errno, "malloc(3)");
			goto cleanup;
		}

		if (f_stat.st_size != read(f_fd, n_buf, f_stat.st_size)) {
			dump_path_error(errno, "read(2)", script);
			goto cleanup;
		}

		for (off_t i = 0; i < f_stat.st_size; i++) {
			if (n_buf[i] != 0)
				continue;
			n_argc++;
		}

		if (n_buf[f_stat.st_size - 1] != 0)
			n_argc++;
	}

	close(f_fd); f_fd = -1;

    char ** n_argv = calloc(n_argc + /* trailing NULL pointer */ 1, sizeof(size_t));
	if (n_argv == NULL) {
		dump_error(errno, "malloc(3)");
		goto cleanup;
	}

	n_argv[0] = program;
	for (int i = 0; i < argc; i++) {
		n_argv[i + 1] = argv[i];
	}
	n_argc = n_argc_base;

	if (f_stat.st_size != 0) {
		char * t = n_buf;
		for (off_t i = 0; i < f_stat.st_size; i++) {
			if (n_buf[i] != 0)
				continue;

			n_argv[n_argc++] = t;
			t = &n_buf[i + 1];
		}

		if (n_buf[f_stat.st_size - 1] != 0) {
			n_argv[n_argc++] = t;
		}
	}

	if (b_del) {
		unlink(script);
		b_del = 0;
	}

	execvp(n_argv[0], n_argv);
	// execution follows here in case of errors
	n_ret = errno;
	dump_error(n_ret, "execvp(3)");
	return n_ret;

cleanup:
	if (f_fd >= 0) {
		close(f_fd);
	}

	if (b_del) {
		unlink(script);
	}

	return n_ret;
}

static void dump_error(int error_num, const char * where)
{
	static char e_buf[8192];
	char * e_str = NULL;

	memset(&e_buf, 0, sizeof(e_buf));
	e_str = strerror_r(error_num, e_buf, sizeof(e_buf) - 1);
	fprintf(stderr, "%s error %d: %s\n", where, error_num, e_str);
}

static void dump_path_error(int error_num, const char * where, const char * name)
{
	static char e_buf[8192];
	char * e_str = NULL;

	memset(&e_buf, 0, sizeof(e_buf));
	e_str = strerror_r(error_num, e_buf, sizeof(e_buf) - 1);
	fprintf(stderr, "%s path '%s' error %d: %s\n", where, name, error_num, e_str);
}
