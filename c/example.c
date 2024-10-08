#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
// #include <sdfgen.h>

void *sdfgen_create();
void *sdfgen_to_xml();
void *sdfgen_pd(char *name, char *elf);
void *sdfgen_sddf_init(char *path);
void *sdfgen_sddf_i2c(void *device, void *driver, void *virt);
void sdfgen_sddf_i2c_client_add(void *i2c_system, void *client);
bool sdfgen_sddf_i2c_connect(void *i2c_system);
void sdfgen_pd_set_priority(void *pd, uint8_t priority);

int main() {
    sdfgen_sddf_init("/Users/ivanv/ts/lionsos_tutorial/lionsos/dep/sddf");

    void *sdf = sdfgen_create();
    void *i2c_reactor_client = sdfgen_pd("i2c_reactor_client", "reactor_client.elf");
    void *i2c_virt = sdfgen_pd("i2c_virt", "i2c_virt.elf");
    void *i2c_reactor_driver = sdfgen_pd("i2c_reactor_driver", "reactor_driver.elf");

    void *i2c_system = sdfgen_sddf_i2c(NULL, i2c_reactor_driver, i2c_virt);
    sdfgen_sddf_i2c_client_add(i2c_system, i2c_reactor_client);

    sdfgen_sddf_i2c_connect(i2c_system);

    sdfgen_pd_set_priority(i2c_reactor_driver, 200);
    sdfgen_pd_set_priority(i2c_virt, 199);
    sdfgen_pd_set_priority(i2c_reactor_client, 198);

    char *xml = sdfgen_to_xml();
    printf("%s", xml);
}
