from __future__ import annotations
import ctypes
from ctypes import c_void_p, c_char_p, c_uint8, c_uint32, c_bool, POINTER, byref
from typing import Optional, Tuple

libsdfgen = ctypes.CDLL("/Users/ivanv/ts/microkit_sdf_gen/zig-out/lib/csdfgen")

libsdfgen.sdfgen_create.restype = c_void_p

libsdfgen.sdfgen_destroy.restype = None
libsdfgen.sdfgen_destroy.argtypes = [c_void_p]

libsdfgen.sdfgen_dtb_parse_from_bytes.restype = c_void_p
libsdfgen.sdfgen_dtb_parse_from_bytes.argtypes = [c_char_p, c_uint32]

libsdfgen.sdfgen_dtb_destroy.restype = None
libsdfgen.sdfgen_dtb_destroy.argtypes = [c_void_p]

libsdfgen.sdfgen_dtb_node.restype = c_void_p
libsdfgen.sdfgen_dtb_node.argtypes = [c_void_p, c_char_p]

libsdfgen.sdfgen_add_pd.restype = None
libsdfgen.sdfgen_add_pd.argtypes = [c_void_p, c_void_p]

libsdfgen.sdfgen_pd_set_priority.restype = None
libsdfgen.sdfgen_pd_set_priority.argtypes = [c_void_p, c_uint8]

libsdfgen.sdfgen_to_xml.restype = c_char_p
libsdfgen.sdfgen_to_xml.argtypes = [c_void_p]

libsdfgen.sdfgen_channel_create.restype = c_void_p
libsdfgen.sdfgen_channel_create.argtypes = [c_void_p, c_void_p]
libsdfgen.sdfgen_channel_destroy.restype = None
libsdfgen.sdfgen_channel_destroy.argtypes = [c_void_p]

libsdfgen.sdfgen_pd_create.restype = c_void_p
libsdfgen.sdfgen_pd_create.argtypes = [c_char_p, c_char_p]
libsdfgen.sdfgen_pd_destroy.restype = None
libsdfgen.sdfgen_pd_destroy.argtypes = [c_void_p]

libsdfgen.sdfgen_pd_add_child.restype = c_uint8
libsdfgen.sdfgen_pd_add_child.argtypes = [c_void_p, c_void_p, POINTER(c_uint8)]

libsdfgen.sdfgen_sddf_timer.restype = c_void_p
libsdfgen.sdfgen_sddf_timer.argtypes = [c_void_p, c_void_p, c_void_p]
libsdfgen.sdfgen_sddf_timer_destroy.restype = None
libsdfgen.sdfgen_sddf_timer_destroy.argtypes = [c_void_p]

libsdfgen.sdfgen_sddf_timer_add_client.restype = None
libsdfgen.sdfgen_sddf_timer_add_client.argtypes = [c_void_p, c_void_p]

libsdfgen.sdfgen_sddf_timer_connect.restype = c_bool
libsdfgen.sdfgen_sddf_timer_connect.argtypes = [c_void_p]

libsdfgen.sdfgen_sddf_i2c.restype = c_void_p
libsdfgen.sdfgen_sddf_i2c.argtypes = [c_void_p, c_void_p, c_void_p, c_void_p]
libsdfgen.sdfgen_sddf_i2c_destroy.restype = None
libsdfgen.sdfgen_sddf_i2c_destroy.argtypes = [c_void_p]

libsdfgen.sdfgen_sddf_i2c_add_client.restype = c_void_p
libsdfgen.sdfgen_sddf_i2c_add_client.argtypes = [c_void_p, c_void_p]

libsdfgen.sdfgen_sddf_i2c_connect.restype = c_bool
libsdfgen.sdfgen_sddf_i2c_connect.argtypes = [c_void_p]

libsdfgen.sdfgen_sddf_block.restype = c_void_p
libsdfgen.sdfgen_sddf_block.argtypes = [c_void_p, c_void_p, c_void_p, c_void_p]

libsdfgen.sdfgen_sddf_block_add_client.restype = c_void_p
libsdfgen.sdfgen_sddf_block_add_client.argtypes = [c_void_p, c_void_p]

libsdfgen.sdfgen_sddf_block_connect.restype = c_bool
libsdfgen.sdfgen_sddf_block_connect.argtypes = [c_void_p]

libsdfgen.sdfgen_sddf_serial.restype = c_void_p
libsdfgen.sdfgen_sddf_serial.argtypes = [c_void_p, c_void_p, c_void_p, c_void_p, c_void_p]
libsdfgen.sdfgen_sddf_serial_destroy.restype = None
libsdfgen.sdfgen_sddf_serial_destroy.argtypes = [c_void_p]

libsdfgen.sdfgen_sddf_serial_add_client.restype = None
libsdfgen.sdfgen_sddf_serial_add_client.argtypes = [c_void_p, c_void_p]

libsdfgen.sdfgen_sddf_serial_connect.restype = c_bool
libsdfgen.sdfgen_sddf_serial_connect.argtypes = [c_void_p]

libsdfgen.sdfgen_sddf_net.restype = c_void_p
libsdfgen.sdfgen_sddf_net.argtypes = [c_void_p, c_void_p, c_void_p, c_void_p, c_void_p]
libsdfgen.sdfgen_sddf_net_destroy.restype = None
libsdfgen.sdfgen_sddf_net_destroy.argtypes = [c_void_p]

libsdfgen.sdfgen_sddf_net_add_client_with_copier.restype = None
libsdfgen.sdfgen_sddf_net_add_client_with_copier.argtypes = [
    c_void_p,
    c_void_p,
    c_void_p,
    POINTER(c_uint8)
]

libsdfgen.sdfgen_sddf_net_connect.restype = c_bool
libsdfgen.sdfgen_sddf_net_connect.argtypes = [c_void_p]


class DeviceTree:
    _obj: c_void_p
    _bytes: bytearray

    def __init__(self, data: bytearray):
        # Data is stored explicitly so it is not freed in GC.
        # The DTB parser assumes the memory does not go away.
        self._bytes = data
        self._obj = libsdfgen.sdfgen_dtb_parse_from_bytes(c_char_p(data), len(data))
        assert self._obj is not None

    def __del__(self):
        libsdfgen.sdfgen_dtb_destroy(self._obj)

    class Node:
        # TODO: does having a node increase the ref count for the
        # device tree
        def __init__(self, device_tree: DeviceTree, node: str):
            c_node = c_char_p(node.encode("utf-8"))
            self._obj = libsdfgen.sdfgen_dtb_node(device_tree._obj, c_node)

            if self._obj is None:
                raise Exception(f"could not find DTB node '{node}'")

    def node(self, name: str):
        return DeviceTree.Node(self, name)


class ProtectionDomain:
    _obj: c_void_p

    def __init__(self, name: str, program_image: str, priority=None):
        c_name = c_char_p(name.encode("utf-8"))
        c_program_image = c_char_p(program_image.encode("utf-8"))
        self._obj = libsdfgen.sdfgen_pd_create(c_name, c_program_image)
        if priority is not None:
            libsdfgen.sdfgen_pd_set_priority(self._obj, priority)

    def add_child_pd(self, child_pd: ProtectionDomain, child_id=None) -> int:
        c_child_id = byref(c_uint8(child_id)) if child_id else None

        returned_id = libsdfgen.sdfgen_pd_add_child(self._obj, child_pd._obj, c_child_id)
        if returned_id is None:
            raise Exception("Could not allocate child PD ID")

        return returned_id

    def __del__(self):
        libsdfgen.sdfgen_pd_destroy(self._obj)


class Channel:
    obj: c_void_p

    # TODO: handle options
    def __init__(
        self,
        a: ProtectionDomain,
        b: ProtectionDomain,
        pp_a=False,
        pp_b=False,
        notify_a=True,
        notify_b=True
    ) -> None:
        self._obj = libsdfgen.sdfgen_channel_create(a._obj, b._obj)

    def __del__(self):
        libsdfgen.sdfgen_channel_destroy(self._obj)


class SystemDescription:
    _obj: c_void_p

    def __init__(self, arch: int, paddr_top: int) -> None:
        self._obj = libsdfgen.sdfgen_create(arch, paddr_top)

    def __del__(self):
        libsdfgen.sdfgen_destroy(self._obj)

    def add_pd(self, pd: ProtectionDomain):
        libsdfgen.sdfgen_add_pd(self._obj, pd._obj)

    def xml(self):
        return libsdfgen.sdfgen_to_xml(self._obj).decode("utf-8")


class Sddf:
    def __init__(self, path: str):
        libsdfgen.sdfgen_sddf_init(c_char_p(path.encode("utf-8")))

    def __del__(self):
        # TODO
        pass

    class Serial:
        _obj: c_void_p

        def __init__(
            self,
            sdf: SystemDescription,
            device: Optional[DeviceTree.Node],
            driver: ProtectionDomain,
            virt_tx: ProtectionDomain,
            virt_rx: Optional[ProtectionDomain]
        ) -> None:
            if device is None:
                device_obj = None
            else:
                device_obj = device._obj

            if virt_rx is None:
                virt_rx_obj = None
            else:
                virt_rx_obj = virt_rx._obj

            self._obj = libsdfgen.sdfgen_sddf_serial(
                sdf._obj, device_obj, driver._obj, virt_tx._obj, virt_rx_obj
            )

        def add_client(self, client: ProtectionDomain):
            libsdfgen.sdfgen_sddf_serial_add_client(self._obj, client._obj)

        def connect(self) -> bool:
            return libsdfgen.sdfgen_sddf_serial_connect(self._obj)

        def __del__(self):
            libsdfgen.sdfgen_sddf_serial_destroy(self._obj)

    class I2c:
        _obj: c_void_p

        def __init__(
            self,
            sdf: SystemDescription,
            device: Optional[DeviceTree.Node],
            driver: ProtectionDomain,
            virt: ProtectionDomain
        ) -> None:
            if device is None:
                device_obj = None
            else:
                device_obj = device._obj

            self._obj = libsdfgen.sdfgen_sddf_i2c(sdf._obj, device_obj, driver._obj, virt._obj)

        def add_client(self, client: ProtectionDomain):
            libsdfgen.sdfgen_sddf_i2c_add_client(self._obj, client._obj)

        def connect(self) -> bool:
            return libsdfgen.sdfgen_sddf_i2c_connect(self._obj)

        def __del__(self):
            libsdfgen.sdfgen_sddf_i2c_destroy(self._obj)

    class Block:
        _obj: c_void_p

        def __init__(
            self,
            sdf: SystemDescription,
            device: Optional[DeviceTree.Node],
            driver: ProtectionDomain,
            virt: ProtectionDomain
        ) -> None:
            if device is None:
                device_obj = None
            else:
                device_obj = device._obj

            self._obj = libsdfgen.sdfgen_sddf_block(sdf._obj, device_obj, driver._obj, virt._obj)

        def add_client(self, client: ProtectionDomain):
            libsdfgen.sdfgen_sddf_block_add_client(self._obj, client._obj)

        def connect(self) -> bool:
            return libsdfgen.sdfgen_sddf_block_connect(self._obj)

        def __del__(self):
            libsdfgen.sdfgen_sddf_block_destroy(self._obj)

    class Network:
        _obj: c_void_p

        def __init__(
            self,
            sdf: SystemDescription,
            device: Optional[DeviceTree.Node],
            driver: ProtectionDomain,
            virt_tx: ProtectionDomain,
            virt_rx: ProtectionDomain
        ) -> None:
            if device is None:
                device_obj = None
            else:
                device_obj = device._obj

            self._obj = libsdfgen.sdfgen_sddf_net(
                sdf._obj, device_obj, driver._obj, virt_tx._obj, virt_rx._obj
            )

        def add_client_with_copier(
            self,
            client: ProtectionDomain,
            copier: ProtectionDomain,
            mac_addr: Tuple[int, int, int, int, int, int]
        ) -> None:
            if len(mac_addr) != 6:
                raise Exception("invalid mac address length")

            c_mac_addr = (ctypes.c_uint8 * len(mac_addr))(*mac_addr)
            libsdfgen.sdfgen_sddf_net_add_client_with_copier(
                self._obj, client._obj, copier._obj, c_mac_addr
            )

        def connect(self) -> bool:
            return libsdfgen.sdfgen_sddf_net_connect(self._obj)

        def __del__(self):
            libsdfgen.sdfgen_sddf_net_destroy(self._obj)

    class Timer:
        _obj: c_void_p

        def __init__(
            self,
            sdf: SystemDescription,
            device: Optional[DeviceTree.Node],
            driver: ProtectionDomain
        ) -> None:
            if device is None:
                device_obj = None
            else:
                device_obj = device._obj

            self._obj: c_void_p = libsdfgen.sdfgen_sddf_timer(sdf._obj, device_obj, driver._obj)

        def add_client(self, client: ProtectionDomain):
            libsdfgen.sdfgen_sddf_timer_add_client(self._obj, client._obj)

        def connect(self) -> bool:
            return libsdfgen.sdfgen_sddf_timer_connect(self._obj)

        def __del__(self):
            libsdfgen.sdfgen_sddf_timer_destroy(self._obj)
