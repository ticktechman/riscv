#include <cstdint>

#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

#include <libelf/gelf.h>
#include <libelf/libelf.h>
#include <svdpi.h>

extern "C" {

typedef struct packed {
  uint64_t END;
  uint64_t BASE;
} mmap_t;

int elf_parse(const char *filename, const char *sec, mmap_t *mapping) {
  if (elf_version(EV_CURRENT) == EV_NONE) {
    return 1;
  }

  int fd = open(filename, O_RDONLY);
  if (fd < 0) {
    return 1;
  }

  Elf *elf = elf_begin(fd, ELF_C_READ, nullptr);
  if (!elf) {
    close(fd);
    return 1;
  }

  size_t shstrndx;
  if (elf_getshdrstrndx(elf, &shstrndx) != 0) {
    elf_end(elf);
    close(fd);
    return 1;
  }

  bool found = false;
  Elf_Scn *scn = nullptr;

  while ((scn = elf_nextscn(elf, scn)) != NULL) {
    GElf_Shdr shdr;
    if (gelf_getshdr(scn, &shdr) == nullptr) {
      continue;
    }

    const char *sec_name = elf_strptr(elf, shstrndx, shdr.sh_name);
    if (!sec_name)
      continue;

    if (strcmp(sec_name, sec) == 0) {
      found = true;

      Elf64_Addr start_vma = shdr.sh_addr;
      Elf64_Addr end_vma = shdr.sh_addr + shdr.sh_size;

      Elf64_Off file_start = shdr.sh_offset;
      Elf64_Off file_end = shdr.sh_offset + shdr.sh_size;

      mapping->BASE = (start_vma);
      mapping->END = (end_vma);

      break;
    } else {
      mapping->BASE = 0;
      mapping->END = 0;
    }
  }

  elf_end(elf);
  close(fd);
  return found ? 0 : 1;
}

int elf_load_sec(const char *filename, const char *sec, void *addr, size_t sz) {
  if (elf_version(EV_CURRENT) == EV_NONE) {
    return 1;
  }

  int fd = open(filename, O_RDONLY);
  if (fd < 0) {
    return 1;
  }

  Elf *elf = elf_begin(fd, ELF_C_READ, nullptr);
  if (!elf) {
    close(fd);
    return 1;
  }

  size_t shstrndx;
  if (elf_getshdrstrndx(elf, &shstrndx) != 0) {
    elf_end(elf);
    close(fd);
    return 1;
  }

  bool found = false;
  Elf_Scn *scn = nullptr;

  while ((scn = elf_nextscn(elf, scn)) != NULL) {
    GElf_Shdr shdr;
    if (gelf_getshdr(scn, &shdr) == nullptr) {
      continue;
    }

    const char *sec_name = elf_strptr(elf, shstrndx, shdr.sh_name);
    if (!sec_name)
      continue;

    if (strcmp(sec_name, sec) == 0) {
      found = true;

      Elf64_Off file_start = shdr.sh_offset;
      Elf64_Off file_end = shdr.sh_offset + shdr.sh_size;

      size_t readsz = sz > shdr.sh_size ? shdr.sh_size : sz;
      int readed = pread(fd, addr, readsz, shdr.sh_offset);
      printf("total readed: %d %p\n", readed, addr);

      break;
    }
  }

  elf_end(elf);
  close(fd);
  return found ? 0 : 1;
}

int elf_parse_mapping(const char *elf, mmap_t *mapping) {
  elf_parse(elf, ".text.init", mapping);
  elf_parse(elf, ".tohost", mapping + 1);
  elf_parse(elf, ".data", mapping + 2);
  if (mapping[2].BASE == 0 || mapping[2].END == 0) {
    elf_parse(elf, ".bss", mapping + 2);
  }
  return 0;
}

// int main(int argc, char *argv[]) {
//   if (argc != 2) {
//     return 1;
//   }
//   const char *elf = argv[1];
//
//   map_t mapping[3] = {0};
//   elf_parse_mapping(elf, mapping);
//
//   uint8_t *buf = (uint8_t *)malloc(1024 * 1024);
//
//   for (size_t i = 0; i < 3; i++) {
//     printf("start:%llx end:%llx\n", mapping[i].START, mapping[i].END);
//   }
//   elf_load_sec(elf, ".text.init", buf, 1024 * 1024);
//   elf_load_sec(elf, ".data", buf, 1024 * 1024);
//
//   return 0;
// }
}
