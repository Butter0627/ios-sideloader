#pragma once

char *core_init(void);
void core_set_support_dir(const char *path_ptr);
char *core_pairing_status(void);
char *core_start_local_pairing(void);
void core_free_string(char *ptr);
