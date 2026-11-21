#pragma once

#include <stdbool.h>

char *core_init(void);
void core_set_support_dir(const char *path_ptr);
char *core_pairing_status(void);
char *core_start_local_pairing(void);
char *core_apple_status(void);
char *core_apple_login(const char *email_ptr, const char *password_ptr);
char *core_apple_submit_2fa(const char *code_ptr);
char *core_apple_confirm_7460(bool allow_cleanup);
char *core_ipa_status(void);
char *core_ipa_select(const char *ipa_path_ptr);
char *core_ipa_sign_and_install(const char *app_group_ptr, const char *custom_bundle_id_ptr);
void core_free_string(char *ptr);
