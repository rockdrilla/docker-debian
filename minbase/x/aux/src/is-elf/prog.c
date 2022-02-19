/* is-elf: trivial file type check for ELF files
 *
 * SPDX-License-Identifier: BSD-3-Clause
 * (c) 2022, Konstantin Demin
 * 
 * Rough alternative (but slow):
 *   file -L -N -F '|' -p -S /path/to/file \
 *   | mawk -F '|' 'BEGIN { ORS="\0"; } $2 ~ "^ ?ELF " { print $1; }'
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <sys/stat.h>

#include <elf.h>
#include <endian.h>

char n_buf[sizeof(Elf32_Ehdr)];

char e_buf[4096];

void usage(void)
{
	fprintf(stderr,
		"Usage: is-elf <file>\n"
		"  <file> - file meant to be ELF\n"
	);
}

int bo_target = ELFDATANONE;
uint16_t u16toh(uint16_t value)
{
	return (bo_target == ELFDATA2LSB) ? le16toh(value) : be16toh(value);
}
uint32_t u32toh(uint32_t value)
{
	return (bo_target == ELFDATA2LSB) ? le32toh(value) : be32toh(value);
}

int main(int argc, char * argv[])
{
	int          f_fd = -1;
	int         n_ret = 1; // EINVAL ?..
	char      * e_str = NULL;
	Elf32_Ehdr * ehdr = (void *) n_buf;
	struct stat f_stat;

	if (argc == 1) {
		usage();
		return 0;
	}

	if (argc != 2) {
		usage();
		return EINVAL;
	}

	memset(&e_buf, 0, sizeof(e_buf));

	f_fd = open(argv[1], O_RDONLY);
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

	if (f_stat.st_size < (off_t) sizeof(n_buf)) goto cleanup;

	if (sizeof(n_buf) != read(f_fd, n_buf, sizeof(n_buf))) {
		n_ret = errno;
		e_str = strerror_r(n_ret, e_buf, sizeof(e_buf));
		fprintf(stderr, "read(2) error %d: %s\n", n_ret, e_str);
		goto cleanup;
	}

	close(f_fd); f_fd = -1;

	if (n_buf[0] != ELFMAG0) goto cleanup;
	if (n_buf[1] != ELFMAG1) goto cleanup;
	if (n_buf[2] != ELFMAG2) goto cleanup;
	if (n_buf[3] != ELFMAG3) goto cleanup;

	switch (n_buf[EI_CLASS]) {
	case ELFCLASS32:
		// -fallthrough
	case ELFCLASS64:
		break;
	default:
		goto cleanup;
	}

	bo_target = n_buf[EI_DATA];
	switch (bo_target) {
	case ELFDATA2LSB:
		// -fallthrough
	case ELFDATA2MSB:
		break;
	default:
		goto cleanup;
	}

	switch (n_buf[EI_VERSION]) {
	case EV_CURRENT:
		break;
	default:
		goto cleanup;
	}

	switch (n_buf[EI_OSABI]) {
	case ELFOSABI_SYSV:
		// -fallthrough
	case ELFOSABI_GNU:
		break;
	default:
		goto cleanup;
	}

	switch (u16toh(ehdr->e_type)) {
	case ET_REL:
		// -fallthrough
	case ET_EXEC:
		// -fallthrough
	case ET_DYN:
		break;
	default:
		goto cleanup;
	}

	switch (u16toh(ehdr->e_machine)) {
	case EM_386:
		// -fallthrough
	case EM_PPC64:
		// -fallthrough
	case EM_S390:
		// -fallthrough
	case EM_X86_64:
		// -fallthrough
	case EM_AARCH64:
		break;
	default:
		goto cleanup;
	}

	switch (u32toh(ehdr->e_version)) {
	case EV_CURRENT:
		break;
	default:
		goto cleanup;
	}

	n_ret = 0;
	fprintf(stdout, "%s%c", argv[1], 0);

cleanup:
	if (f_fd >= 0) {
		close(f_fd);
	}

	return n_ret;
}
