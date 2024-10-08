#include <stdbool.h>
#include <stdint.h>

void *sdfgen_create();
void *sdfgen_to_xml(void *sdf);

void *sdfgen_pd_create(char *name, char *elf);
void *sdfgen_pd_add(void *sdf, void *pd);
void sdfgen_pd_set_priority(void *pd, uint8_t priority);

void *sdfgen_sddf_init(char *path);

void *sdfgen_sddf_i2c(void *sdf, void *device, void *driver, void *virt);
void sdfgen_sddf_i2c_client_add(void *i2c_system, void *client);
bool sdfgen_sddf_i2c_connect(void *i2c_system);
