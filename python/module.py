from __future__ import annotations
import ctypes
import importlib.util
from ctypes import c_void_p, c_char_p, c_uint8, c_uint32, c_bool, POINTER, byref
from typing import Optional, Tuple
from enum import IntEnum

libsdfgen = ctypes.CDLL(importlib.util.find_spec("csdfgen").origin)

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
libsdfgen.sdfgen_pd_set_budget.restype = None
libsdfgen.sdfgen_pd_set_budget.argtypes = [c_void_p, c_uint8]
libsdfgen.sdfgen_pd_set_period.restype = None
libsdfgen.sdfgen_pd_set_period.argtypes = [c_void_p, c_uint8]
libsdfgen.sdfgen_pd_set_stack_size.restype = None
libsdfgen.sdfgen_pd_set_stack_size.argtypes = [c_void_p, c_uint32]

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
libsdfgen.sdfgen_sddf_timer_serialise_config.restype = c_bool
libsdfgen.sdfgen_sddf_timer_serialise_config.argtypes = [c_void_p, c_char_p]

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

libsdfgen.sdfgen_sddf_serial_serialise_config.restype = c_bool
libsdfgen.sdfgen_sddf_serial_serialise_config.argtypes = [c_void_p, c_char_p]

libsdfgen.sdfgen_sddf_net.restype = c_void_p
libsdfgen.sdfgen_sddf_net.argtypes = [c_void_p, c_void_p, c_void_p, c_void_p, c_void_p]
libsdfgen.sdfgen_sddf_net_destroy.restype = None
libsdfgen.sdfgen_sddf_net_destroy.argtypes = [c_void_p]

libsdfgen.sdfgen_sddf_net_add_client_with_copier.restype = c_bool
libsdfgen.sdfgen_sddf_net_add_client_with_copier.argtypes = [
    c_void_p,
    c_void_p,
    c_void_p,
    c_char_p
]

libsdfgen.sdfgen_sddf_net_connect.restype = c_bool
libsdfgen.sdfgen_sddf_net_connect.argtypes = [c_void_p]

libsdfgen.sdfgen_sddf_net_serialise_config.restype = c_bool
libsdfgen.sdfgen_sddf_net_serialise_config.argtypes = [c_void_p, c_char_p]

class DeviceTree:
    _obj: c_void_p
    _bytes: bytes

    def __init__(self, data: bytes):
        """
        Parse a Device Tree Blob (.dtb) and use it to get nodes
        for generating sDDF device classes or other components.
        """
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

    def node(self, name: str) -> DeviceTree.Node:
        """
        Given a parsed DeviceTree, find the specific node based on the node names.
        Child nodes can be referenced by separating the parent and child node name
        by '/'.

        Example:

        .. code-block:: python

            dtb = DeviceTree(dtb_bytes)
            dtb.node("soc/timer@13050000")

        would be used to access the timer device on a Device Tree that looked like:

        .. code-block::

            soc {
                timer@13050000 {
                    ...
                };
            };
        """
        return DeviceTree.Node(self, name)


class SystemDescription:
    """
    Class for describing a Microkit system. Manages all Microkit resources such as
    Protection Domains, Memory Regions, Channels, etc.
    """

    _obj: c_void_p

    class Arch(IntEnum):
        """Target architecture. Used to resolve architecture specific features or attributes."""
        # Important that this aligns with sdfgen_arch_t in the C bindings.
        AARCH32 = 0,
        AARCH64 = 1,
        RISCV32 = 2,
        RISCV64 = 3,
        X86 = 4,
        X86_64 = 5,

    class ProtectionDomain:
        _obj: c_void_p

        def __init__(
            self,
            name: str,
            program_image: str,
            priority: Optional[int] = None,
            budget: Optional[int] = None,
            period: Optional[int] = None,
            stack_size: Optional[int] = None
        ) -> None:
            c_name = c_char_p(name.encode("utf-8"))
            c_program_image = c_char_p(program_image.encode("utf-8"))
            self._obj = libsdfgen.sdfgen_pd_create(c_name, c_program_image)
            if priority is not None:
                libsdfgen.sdfgen_pd_set_priority(self._obj, priority)
            if budget is not None:
                libsdfgen.sdfgen_pd_set_budget(self._obj, budget)
            if period is not None:
                libsdfgen.sdfgen_pd_set_period(self._obj, period)
            if stack_size is not None:
                libsdfgen.sdfgen_pd_set_stack_size(self._obj, stack_size)

        def add_child_pd(self, child_pd: ProtectionDomain, child_id=None) -> int:
            c_child_id = byref(c_uint8(child_id)) if child_id else None

            returned_id = libsdfgen.sdfgen_pd_add_child(self._obj, child_pd._obj, c_child_id)
            if returned_id is None:
                raise Exception("Could not allocate child PD ID")

            return returned_id

        def __del__(self):
            libsdfgen.sdfgen_pd_destroy(self._obj)


    class Channel:
        _obj: c_void_p

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

    def __init__(self, arch: Arch, paddr_top: int) -> None:
        """
        Create a System Description
        """
        self._obj = libsdfgen.sdfgen_create(arch.value, paddr_top)

    def __del__(self):
        libsdfgen.sdfgen_destroy(self._obj)

    def add_pd(self, pd: ProtectionDomain):
        libsdfgen.sdfgen_add_pd(self._obj, pd._obj)

    def xml(self) -> str:
        """Generate the XML view of the System Description Format for consumption by the Microkit."""
        return libsdfgen.sdfgen_to_xml(self._obj).decode("utf-8")


class Sddf:
    """
    Class for creating I/O systems based on the seL4 Device Driver Framework (sDDF).

    There is a Python class for each device class (e.g Block, Network). They all follow
    the pattern of being initialised, then having clients added, and then being connected
    before the final SDF is generated.
    """
    def __init__(self, path: str):
        """
        :param path: str to the root of the sDDF source code.
        """
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
            """Add a new client connection to the serial system."""
            libsdfgen.sdfgen_sddf_serial_add_client(self._obj, client._obj)

        def connect(self) -> bool:
            """
            Construct and all resources to the associated SystemDescription, returns whether successful.

            Must have all clients and options set before calling.

            Cannot be called more than once.
            """
            return libsdfgen.sdfgen_sddf_serial_connect(self._obj)

        def serialise_config(self, output: str) -> bool:
            c_output = c_char_p(output.encode("utf-8"))
            return libsdfgen.sdfgen_sddf_serial_serialise_config(self._obj, c_output)

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
            *,
            mac_addr: Optional[str] = None
        ) -> None:
            """
            Add a client connected to a copier component for RX traffic.

            :param copier: must be unique to this client, cannot be used with any other client.
            :param mac_addr: must be unique to the Network system.
            """
            if mac_addr is not None and len(mac_addr) != 17:
                raise Exception("invalid MAC address length")

            c_mac_addr = c_char_p(0)
            if mac_addr is not None:
                c_mac_addr = c_char_p(mac_addr.encode("utf-8"))
            ret = libsdfgen.sdfgen_sddf_net_add_client_with_copier(
                self._obj, client._obj, copier._obj, c_mac_addr
            )
            if ret == 0:
                return
            elif ret == 1:
                raise Exception(f"duplicate MAC address given '{mac_addr}'")
            elif ret == 2:
                raise Exception(f"duplicate client given '{client}'")
            elif ret == 3:
                raise Exception(f"duplicate copier given '{copier}'")
            else:
                raise Exception("internal error")

        def connect(self) -> bool:
            return libsdfgen.sdfgen_sddf_net_connect(self._obj)

        def serialise_config(self, output: str) -> bool:
            c_output = c_char_p(output.encode("utf-8"))
            return libsdfgen.sdfgen_sddf_net_serialise_config(self._obj, c_output)

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

        def serialise_config(self, output: str) -> bool:
            c_output = c_char_p(output.encode("utf-8"))
            return libsdfgen.sdfgen_sddf_timer_serialise_config(self._obj, c_output)

        def __del__(self):
            libsdfgen.sdfgen_sddf_timer_destroy(self._obj)
