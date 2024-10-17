/* C bindings for the sdfgen tooling */

#include <stdbool.h>
#include <stdint.h>

/* High-level system functions */
void *sdfgen_create();
void sdfgen_deinit(void *sdf);
void *sdfgen_to_xml(void *sdf);

/* DTB-related functionality */

// Parse the DTB at a given path
// Returns NULL if the path cannot be accessed or the bytes cannot be
// parsed.
void *sdfgen_dtb_parse(char *path);
void *sdfgen_dtb_parse_from_bytes(char *bytes, uint32_t size);
void *sdfgen_dtb_deinit(void *blob);

void *sdfgen_dtb_node(void *blob, char *node);

void *sdfgen_pd_create(char *name, char *elf);
void *sdfgen_pd_add(void *sdf, void *pd);
void sdfgen_pd_set_priority(void *pd, uint8_t priority);
void sdfgen_pd_set_pp(void *pd, bool pp);

void *sdfgen_channel_create(void *pd_a, void *pd_b);
void *sdfgen_channel_add(void *sdf, void *channel);

void *sdfgen_sddf_init(char *path);

void *sdfgen_sddf_timer(void *sdf, void *device, void *driver);
void sdfgen_sddf_timer_add_client(void *system, void *client);
bool sdfgen_sddf_timer_connect(void *system);

void *sdfgen_sddf_i2c(void *sdf, void *device, void *driver, void *virt);
void sdfgen_sddf_i2c_add_client(void *system, void *client);
bool sdfgen_sddf_i2c_connect(void *system);

void *sdfgen_sddf_block(void *sdf, void *device, void *driver, void *virt);
void sdfgen_sddf_block_add_client(void *system, void *client);
bool sdfgen_sddf_block_connect(void *system);

void *sdfgen_sddf_net(void *sdf, void *device, void *driver, void *virt_rx, void *virt_tx);
void sdfgen_sddf_net_add_client_with_copier(void *system, void *client, void *copier);
bool sdfgen_sddf_net_connect(void *system);

void *sdfgen_lionsos_fs(void *sdf, void *fs, void *client);
bool sdfgen_lionsos_fs_connect(void *fs_system);
