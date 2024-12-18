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

typedef enum {
    MAP_READ    = 0b001,
    MAP_WRITE   = 0b010,
    MAP_EXECUTE = 0b100,
} sdfgen_map_perms_t;

/* High-level system functions */
void *sdfgen_create(sdfgen_arch_t arch, uint64_t paddr_top);
void sdfgen_deinit(void *sdf);
void *sdfgen_to_xml(void *sdf);

/*** DTB-related functionality ***/

// Parse the DTB at a given path
// Returns NULL if the path cannot be accessed or the bytes cannot be
// parsed.
void *sdfgen_dtb_parse(char *path);
void *sdfgen_dtb_parse_from_bytes(char *bytes, uint32_t size);
void *sdfgen_dtb_destroy(void *blob);

void *sdfgen_dtb_node(void *blob, char *node);

void *sdfgen_add_pd(void *sdf, void *pd);
void *sdfgen_add_mr(void *sdf, void *mr);
void *sdfgen_add_channel(void *sdf, void *ch);

void *sdfgen_pd_create(char *name, char *elf);
void sdfgen_pd_destroy(void *pd);

/* Can specifiy a fixed ID  */
uint8_t *sdfgen_pd_add_child(void *sdf, void *child_pd, uint8_t *child_id);
void sdfgen_pd_add_map(void *pd, void *map);
void sdfgen_pd_set_priority(void *pd, uint8_t priority);
void sdfgen_pd_set_budget(void *pd, uint32_t budget);
void sdfgen_pd_set_period(void *pd, uint32_t period);
void sdfgen_pd_set_stack_size(void *pd, uint32_t stack_size);
bool sdfgen_pd_set_virtual_machine(void *pd, void *vm);

void *sdfgen_vm_create(char *name, void **vcpus, uint32_t num_vcpus);
void sdfgen_vm_destroy(void *vm);
void sdfgen_vm_add_map(void *vm, void *map);

void *sdfgen_vm_vcpu_create(uint8_t id, uint16_t cpu);
void sdfgen_vm_vcpu_destroy(void *vm);

void *sdfgen_channel_create(void *pd_a, void *pd_b);
void sdfgen_channel_destroy(void *ch);
uint8_t sdfgen_channel_get_pd_a_id(void *ch);
uint8_t sdfgen_channel_get_pd_b_id(void *ch);

void *sdfgen_mr_create(char *name, uint64_t size);
void *sdfgen_mr_create_physical(char *name, uint64_t size, uint64_t paddr);
void sdfgen_mr_destroy(void *mr);

void *sdfgen_map_create(void *mr, uint64_t vaddr, sdfgen_map_perms_t perms, bool cached);
void *sdfgen_map_destroy(void *map);

/*** sDDF ***/

typedef enum {
    SDDF_ERROR_NET_DUPLICATE_MAC_ADDR = 1,
    SDDF_ERROR_NET_DUPLICATE_CLIENT = 2,
    SDDF_ERROR_NET_DUPLICATE_COPIER = 3,
} sdfgen_sddf_error_t;

void *sdfgen_sddf_init(char *path);

void *sdfgen_sddf_timer(void *sdf, void *device, void *driver);
void sdfgen_sddf_timer_destroy(void *system);
void sdfgen_sddf_timer_add_client(void *system, void *client);
bool sdfgen_sddf_timer_connect(void *system);
bool sdfgen_sddf_timer_serialise_config(void *system, char *output_dir);

void *sdfgen_sddf_serial(void *sdf, void *device, void *driver, void *virt_tx, void *virt_rx);
void sdfgen_sddf_serial_add_client(void *system, void *client);
bool sdfgen_sddf_serial_connect(void *system);
bool sdfgen_sddf_serial_serialise_config(void *system, char *output_dir);

void *sdfgen_sddf_i2c(void *sdf, void *device, void *driver, void *virt);
void sdfgen_sddf_i2c_destroy(void *system);
void sdfgen_sddf_i2c_add_client(void *system, void *client);
bool sdfgen_sddf_i2c_connect(void *system);
bool sdfgen_sddf_i2c_serialise_config(void *system, char *output_dir);

void *sdfgen_sddf_block(void *sdf, void *device, void *driver, void *virt);
void sdfgen_sddf_block_destroy(void *system);
void sdfgen_sddf_block_add_client(void *system, void *client);
bool sdfgen_sddf_block_connect(void *system);
bool sdfgen_sddf_block_serialise_config(void *system, char *output_dir);

void *sdfgen_sddf_net(void *sdf, void *device, void *driver, void *virt_rx, void *virt_tx);
void sdfgen_sddf_net_destroy(void *system);
sdfgen_sddf_error_t sdfgen_sddf_net_add_client_with_copier(void *system, void *client, void *copier, uint8_t mac_addr[6]);
bool sdfgen_sddf_net_connect(void *system);
bool sdfgen_sddf_net_serialise_config(void *system, char *output_dir);

/*** LionsOS ***/

void *sdfgen_lionsos_fs(void *sdf, void *fs, void *client);
bool sdfgen_lionsos_fs_connect(void *fs_system);
