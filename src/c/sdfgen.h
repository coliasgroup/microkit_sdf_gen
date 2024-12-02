/* C bindings for the sdfgen tooling */

#include <stdbool.h>
#include <stdint.h>

// Must be in sync with the 'Arch' enum definition in sdf.zig.
typedef enum {
    AARCH32 = 0,
    AARCH64 = 1,
    RISCV32 = 2,
    RISCV64 = 3,
    X86 = 4,
    X86_64 = 5,
} sdfgen_arch_t;

/* High-level system functions */
void *sdfgen_create(sdfgen_arch_t arch, uint64_t paddr_top);
void sdfgen_deinit(void *sdf);
void *sdfgen_to_xml(void *sdf);

/* DTB-related functionality */

// Parse the DTB at a given path
// Returns NULL if the path cannot be accessed or the bytes cannot be
// parsed.
void *sdfgen_dtb_parse(char *path);
void *sdfgen_dtb_parse_from_bytes(char *bytes, uint32_t size);
void *sdfgen_dtb_destroy(void *blob);

void *sdfgen_dtb_node(void *blob, char *node);

void *sdfgen_add_pd(void *sdf, void *pd);

void *sdfgen_pd_create(char *name, char *elf);
void sdfgen_pd_destroy(void *pd);

/* Can specifiy a fixed ID  */
uint8_t *sdfgen_pd_add_child(void *sdf, void *child_pd, uint8_t *child_id);
void sdfgen_pd_set_priority(void *pd, uint8_t priority);
void sdfgen_pd_set_budget(void *pd, uint8_t budget);
void sdfgen_pd_set_period(void *pd, uint8_t period);
void sdfgen_pd_set_stack_size(void *pd, uint32_t stack_size);

void *sdfgen_channel_create(void *pd_a, void *pd_b);
void sdfgen_channel_destroy(void *ch);
void *sdfgen_channel_add(void *sdf, void *ch);

void *sdfgen_sddf_init(char *path);

void *sdfgen_sddf_timer(void *sdf, void *device, void *driver);
void sdfgen_sddf_timer_destroy(void *system);
void sdfgen_sddf_timer_add_client(void *system, void *client);
bool sdfgen_sddf_timer_connect(void *system);

void *sdfgen_sddf_serial(void *sdf, void *device, void *driver, void *virt_tx, void *virt_rx);
void sdfgen_sddf_serial_add_client(void *system, void *client);
bool sdfgen_sddf_serial_connect(void *system);

void *sdfgen_sddf_i2c(void *sdf, void *device, void *driver, void *virt);
void sdfgen_sddf_i2c_destroy(void *system);
void sdfgen_sddf_i2c_add_client(void *system, void *client);
bool sdfgen_sddf_i2c_connect(void *system);

void *sdfgen_sddf_block(void *sdf, void *device, void *driver, void *virt);
void sdfgen_sddf_block_destroy(void *system);
void sdfgen_sddf_block_add_client(void *system, void *client);
bool sdfgen_sddf_block_connect(void *system);

void *sdfgen_sddf_net(void *sdf, void *device, void *driver, void *virt_rx, void *virt_tx);
void sdfgen_sddf_net_destroy(void *system);
void sdfgen_sddf_net_add_client_with_copier(void *system, void *client, void *copier, uint8_t mac_addr[6]);
bool sdfgen_sddf_net_connect(void *system);

void *sdfgen_lionsos_fs(void *sdf, void *fs, void *client);
bool sdfgen_lionsos_fs_connect(void *fs_system);
