#include <stdbool.h>
#include <stdint.h>

void *sdfgen_create();
void *sdfgen_to_xml(void *sdf);

void *sdfgen_dtb_parse(char *path);
void *sdfgen_dtb_node(void *blob, char *node);

void *sdfgen_pd_create(char *name, char *elf);
void *sdfgen_pd_add(void *sdf, void *pd);
void sdfgen_pd_set_priority(void *pd, uint8_t priority);

void *sdfgen_sddf_init(char *path);

void *sdfgen_sddf_i2c(void *sdf, void *device, void *driver, void *virt);
void sdfgen_sddf_i2c_add_client(void *system, void *client);
bool sdfgen_sddf_i2c_connect(void *system);

void *sdfgen_sddf_block(void *sdf, void *device, void *driver, void *virt);
void sdfgen_sddf_block_add_client(void *system, void *client);
bool sdfgen_sddf_block_connect(void *system);
