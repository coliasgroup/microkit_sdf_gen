// #define Py_LIMITED_API 0x03090000
#define PY_SSIZE_T_CLEAN

#include <stdbool.h>
#include <sdfgen.h>
#include <Python.h>

typedef struct {
    PyObject_HEAD
    void *sdf;
} SystemDescriptionObject;

typedef struct {
    PyObject_HEAD
    void *blob;
} DeviceTreeObject;

typedef struct {
    PyObject_HEAD
    void *node;
} DeviceTreeNodeObject;

static PyTypeObject DeviceTreeNodeType = {
    .ob_base = PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "sdfgen.DeviceTreeNode",
    .tp_doc = PyDoc_STR("DeviceTreeNode"),
    .tp_basicsize = sizeof(DeviceTreeNodeObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_new = PyType_GenericNew,
};

static int
DeviceTree_init(DeviceTreeObject *self, PyObject *args)
{
    PyObject *bytes;
    // TODO: could make the type needed a bit more lax? Use y* instead?
    if (!PyArg_ParseTuple(args, "S", &bytes)) {
        return -1;
    }
    Py_INCREF(bytes);
    self->blob = sdfgen_dtb_parse_from_bytes(PyBytes_AsString(bytes), PyBytes_Size(bytes));

    return 0;
}

static PyObject *
DeviceTree_node(DeviceTreeObject *self, PyObject *args) {
    char *node_str;
    if (!PyArg_ParseTuple(args, "s", &node_str)) {
        // TODO: raise exception?
        return NULL;
    }
    void *node = sdfgen_dtb_node(self->blob, node_str);
    if (node == NULL) {
        Py_RETURN_NONE;
    }

    // TODO: this depends on the original bytes of the DeviceTreeObject
    // Need to be careful with GC
    DeviceTreeNodeObject *obj = PyObject_New(DeviceTreeNodeObject, &DeviceTreeNodeType);
    obj->node = node;
    Py_INCREF(obj);
    Py_INCREF(self);

    return (PyObject *)obj;
}

static PyMethodDef DeviceTree_methods[] = {
    {"node", (PyCFunction) DeviceTree_node, METH_VARARGS,
     "Get a node in the DeviceTree, returns None if the node does not exist."
    },
    {NULL}  /* Sentinel */
};

static PyTypeObject DeviceTreeType = {
    .ob_base = PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "sdfgen.DeviceTree",
    .tp_doc = PyDoc_STR("DeviceTree"),
    .tp_basicsize = sizeof(DeviceTreeObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc) DeviceTree_init,
    .tp_methods = DeviceTree_methods,
};

typedef struct {
    PyObject_HEAD
    void *pd;
} ProtectionDomainObject;

static int
ProtectionDomain_init(ProtectionDomainObject *self, PyObject *args, PyObject *kwds)
{
    // TODO: check args
    // TODO: handle defaults, better, ideally we wouldn't set the priority unless
    // it was supplied;
    uint8_t priority = 100;
    static char *kwlist[] = { "name", "elf", "priority", NULL };
    char *name;
    char *elf;
    if (!PyArg_ParseTupleAndKeywords(args, kwds, "ss|$h", kwlist, &name, &elf, &priority)) {
        return -1;
    }
    self->pd = sdfgen_pd_create(name, elf);
    sdfgen_pd_set_priority(self->pd, priority);

    return 0;
}

static PyTypeObject ProtectionDomainType = {
    .ob_base = PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "sdfgen.ProtectionDomain",
    .tp_doc = PyDoc_STR("ProtectionDomain"),
    .tp_basicsize = sizeof(ProtectionDomainObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc) ProtectionDomain_init,
};

typedef struct {
    PyObject_HEAD
    void *system;
} SddfNetworkObject;

static int
SddfNetwork_init(SddfNetworkObject *self, PyObject *args)
{
    // TODO: check args
    SystemDescriptionObject *sdf_obj;
    PyObject *device_obj;
    ProtectionDomainObject *driver_obj;
    ProtectionDomainObject *virt_rx_obj;
    ProtectionDomainObject *virt_tx_obj;

    PyArg_ParseTuple(args, "OOOOO", &sdf_obj, &device_obj, &driver_obj, &virt_rx_obj, &virt_tx_obj);

    /* It is valid to pass NULL as the device node pointer, so we figure that out here. */
    void *device;
    if (device_obj == Py_None) {
        device = NULL;
    } else {
        device = ((DeviceTreeNodeObject *)device_obj)->node;
    }

    self->system = sdfgen_sddf_net(sdf_obj->sdf, device, driver_obj->pd, virt_rx_obj->pd, virt_tx_obj->pd);
    return 0;
}

static PyObject *
SddfNetwork_add_client_with_copier(SddfNetworkObject *self, PyObject *args)
{
    // TODO: do we need to count refernce to pds?
    ProtectionDomainObject *client_obj;
    ProtectionDomainObject *copier_obj;

    if (!PyArg_ParseTuple(args, "OO", &client_obj, &copier_obj)) {
        // TODO: raise exception?
        return NULL;
    }

    sdfgen_sddf_net_add_client_with_copier(self->system, client_obj->pd, copier_obj->pd);

    Py_RETURN_NONE;
}

static PyObject *
SddfNetwork_connect(SddfNetworkObject *self, PyObject *Py_UNUSED(ignored))
{
    sdfgen_sddf_net_connect(self->system);

    Py_RETURN_NONE;
}

static PyMethodDef SddfNetwork_methods[] = {
    {"add_client_with_copier", (PyCFunction) SddfNetwork_add_client_with_copier, METH_VARARGS,
     "Add a client with a copier component to the system"
    },
    {"connect", (PyCFunction) SddfNetwork_connect, METH_NOARGS,
     "Generate all resources for system"
    },
    {NULL}  /* Sentinel */
};

static PyTypeObject SddfNetworkType = {
    .ob_base = PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "sdfgen.Sddf.Network",
    .tp_doc = PyDoc_STR("Sddf.Network"),
    .tp_basicsize = sizeof(SddfNetworkObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc) SddfNetwork_init,
    .tp_methods = SddfNetwork_methods,
};

typedef struct {
    PyObject_HEAD
    void *system;
} SddfBlockObject;

static int
SddfBlock_init(SddfBlockObject *self, PyObject *args)
{
    // TODO: check args
    SystemDescriptionObject *sdf_obj;
    PyObject *device_obj;
    ProtectionDomainObject *driver_obj;
    ProtectionDomainObject *virt_obj;

    PyArg_ParseTuple(args, "OOOO", &sdf_obj, &device_obj, &driver_obj, &virt_obj);

    /* It is valid to pass NULL as the device node pointer, so we figure that out here. */
    void *device;
    if (device_obj == Py_None) {
        device = NULL;
    } else {
        device = ((DeviceTreeNodeObject *)device_obj)->node;
    }

    self->system = sdfgen_sddf_block(sdf_obj->sdf, device, driver_obj->pd, virt_obj->pd);
    return 0;
}

static PyObject *
SddfBlock_add_client(SddfBlockObject *self, PyObject *py_pd)
{
    // TODO: do we need to count refernce to py_pd?
    ProtectionDomainObject *pd_obj = (ProtectionDomainObject *)py_pd;
    sdfgen_sddf_block_add_client(self->system, pd_obj->pd);

    Py_RETURN_NONE;
}

static PyObject *
SddfBlock_connect(SddfBlockObject *self, PyObject *Py_UNUSED(ignored))
{
    sdfgen_sddf_block_connect(self->system);

    Py_RETURN_NONE;
}

static PyMethodDef SddfBlock_methods[] = {
    {"add_client", (PyCFunction) SddfBlock_add_client, METH_O,
     "Add a client to the system"
    },
    {"connect", (PyCFunction) SddfBlock_connect, METH_NOARGS,
     "Generate all resources for system"
    },
    {NULL}  /* Sentinel */
};

static PyTypeObject SddfBlockType = {
    .ob_base = PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "sdfgen.Sddf.Block",
    .tp_doc = PyDoc_STR("Sddf.Block"),
    .tp_basicsize = sizeof(SddfBlockObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc) SddfBlock_init,
    .tp_methods = SddfBlock_methods,
};

typedef struct {
    PyObject_HEAD
    void *system;
} SddfI2cObject;

static int
SddfI2c_init(SddfI2cObject *self, PyObject *args)
{
    // TODO: check args
    SystemDescriptionObject *sdf_obj;
    PyObject *device_obj;
    ProtectionDomainObject *driver_obj;
    ProtectionDomainObject *virt_obj;

    PyArg_ParseTuple(args, "OOOO", &sdf_obj, &device_obj, &driver_obj, &virt_obj);

    /* It is valid to pass NULL as the device node pointer, so we figure that out here. */
    void *device;
    if (device_obj == Py_None) {
        device = NULL;
    } else {
        device = ((DeviceTreeNodeObject *)device_obj)->node;
    }

    self->system = sdfgen_sddf_i2c(sdf_obj->sdf, device, driver_obj->pd, virt_obj->pd);
    return 0;
}

static PyObject *
SddfI2c_add_client(SddfI2cObject *self, PyObject *py_pd)
{
    // TODO: do we need to count refernce to py_pd?
    ProtectionDomainObject *pd_obj = (ProtectionDomainObject *)py_pd;
    sdfgen_sddf_i2c_add_client(self->system, pd_obj->pd);

    Py_RETURN_NONE;
}

static PyObject *
SddfI2c_connect(SddfI2cObject *self, PyObject *Py_UNUSED(ignored))
{
    sdfgen_sddf_i2c_connect(self->system);

    Py_RETURN_NONE;
}

static PyMethodDef SddfI2c_methods[] = {
    {"add_client", (PyCFunction) SddfI2c_add_client, METH_O,
     "Add a client to the system"
    },
    {"connect", (PyCFunction) SddfI2c_connect, METH_NOARGS,
     "Generate all resources for system"
    },
    {NULL}  /* Sentinel */
};

static PyTypeObject SddfI2cType = {
    .ob_base = PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "sdfgen.Sddf.I2c",
    .tp_doc = PyDoc_STR("Sddf.I2c"),
    .tp_basicsize = sizeof(SddfI2cObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc) SddfI2c_init,
    .tp_methods = SddfI2c_methods,
};

typedef struct {
    PyObject_HEAD
} SddfObject;

static int
Sddf_init(SddfObject *self, PyObject *args)
{
    // TODO: check if sddf path is null?
    // TODO: handle error case
    char *sddf_path;
    PyArg_ParseTuple(args, "s", &sddf_path);
    sdfgen_sddf_init(sddf_path);

    return 0;
}

static PyTypeObject SddfType = {
    .ob_base = PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "sdfgen.Sddf",
    .tp_doc = PyDoc_STR("Sddf"),
    .tp_basicsize = sizeof(SddfObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc) Sddf_init,
};

static int
SystemDescription_init(SystemDescriptionObject *self, PyObject *args, PyObject *kwds)
{
    self->sdf = sdfgen_create();
    return 0;
}

static PyObject *
SystemDescription_add_pd(SystemDescriptionObject *self, PyObject *py_pd)
{
    // TODO: do we need to count refernce to py_pd?
    ProtectionDomainObject *pd_obj = (ProtectionDomainObject *)py_pd;
    sdfgen_pd_add(self->sdf, pd_obj->pd);

    Py_RETURN_NONE;
}

static PyObject *
SystemDescription_xml(SystemDescriptionObject *self, PyObject *Py_UNUSED(ignored))
{
    return PyUnicode_FromString(sdfgen_to_xml(self->sdf));
}

static PyMethodDef SystemDescription_methods[] = {
    {"xml", (PyCFunction) SystemDescription_xml, METH_NOARGS,
     "Generate and return the XML format"
    },
    {"add_pd", (PyCFunction) SystemDescription_add_pd, METH_O,
     "Add a ProtectionDomain"
    },
    {NULL}  /* Sentinel */
};

static PyTypeObject SystemDescriptionType = {
    .ob_base = PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "sdfgen.SystemDescription",
    .tp_doc = PyDoc_STR("SystemDescription"),
    .tp_basicsize = sizeof(SystemDescriptionObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_new = PyType_GenericNew,
    .tp_init = (initproc) SystemDescription_init,
    .tp_methods = SystemDescription_methods,
};

static PyModuleDef sdfgen_module = {
    .m_base = PyModuleDef_HEAD_INIT,
    .m_name = "sdfgen",
    .m_doc = "Python bindings for the sdfgen tooling",
    .m_size = -1,
};

PyMODINIT_FUNC
PyInit_sdfgen(void)
{
    PyObject *m;

    SddfType.tp_dict = PyDict_New();
    if (!SddfType.tp_dict) {
        return NULL;
    }

    if (PyType_Ready(&SystemDescriptionType) < 0) {
        return NULL;
    }

    if (PyType_Ready(&DeviceTreeType) < 0) {
        return NULL;
    }

    if (PyType_Ready(&DeviceTreeNodeType) < 0) {
        return NULL;
    }

    if (PyType_Ready(&ProtectionDomainType) < 0) {
        return NULL;
    }

    if (PyType_Ready(&SddfI2cType) < 0) {
        return NULL;
    }
    Py_INCREF(&SddfI2cType);
    PyDict_SetItemString(SddfType.tp_dict, "I2c", (PyObject *)&SddfI2cType);

    if (PyType_Ready(&SddfBlockType) < 0) {
        return NULL;
    }
    Py_INCREF(&SddfBlockType);
    PyDict_SetItemString(SddfType.tp_dict, "Block", (PyObject *)&SddfBlockType);

    if (PyType_Ready(&SddfNetworkType) < 0) {
        return NULL;
    }
    Py_INCREF(&SddfNetworkType);
    PyDict_SetItemString(SddfType.tp_dict, "Network", (PyObject *)&SddfNetworkType);

    if (PyType_Ready(&SddfType) < 0) {
        return NULL;
    }

    m = PyModule_Create(&sdfgen_module);
    if (m == NULL) {
        return NULL;
    }

    Py_INCREF(&SystemDescriptionType);
    if (PyModule_AddObject(m, "SystemDescription", (PyObject *) &SystemDescriptionType) < 0) {
        Py_DECREF(&SystemDescriptionType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&DeviceTreeType);
    if (PyModule_AddObject(m, "DeviceTree", (PyObject *) &DeviceTreeType) < 0) {
        Py_DECREF(&DeviceTreeType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&DeviceTreeNodeType);
    if (PyModule_AddObject(m, "DeviceTreeNode", (PyObject *) &DeviceTreeNodeType) < 0) {
        Py_DECREF(&DeviceTreeNodeType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&ProtectionDomainType);
    if (PyModule_AddObject(m, "ProtectionDomain", (PyObject *) &ProtectionDomainType) < 0) {
        Py_DECREF(&ProtectionDomainType);
        Py_DECREF(m);
        return NULL;
    }

    Py_INCREF(&SddfType);
    if (PyModule_AddObject(m, "Sddf", (PyObject *) &SddfType) < 0) {
        Py_DECREF(&SddfType);
        Py_DECREF(m);
        return NULL;
    }

    return m;
}
