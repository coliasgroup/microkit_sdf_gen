const std = @import("std");
const modsdf = @import("sdf");
const py = @cImport({
    @cDefine("Py_LIMITED_API", "3");
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});
const allocator = std.heap.c_allocator;

const PyObject = py.PyObject;
const PyMethodDef = py.PyMethodDef;
const PyModuleDef = py.PyModuleDef;
const PyModuleDef_Base = py.PyModuleDef_Base;
const Py_BuildValue = py.Py_BuildValue;
const PyModule_Create = py.PyModule_Create;
const METH_NOARGS = py.METH_NOARGS;
const PyObject_HEAD = py.PyObject_HEAD;
const PyTypeObject = py.PyTypeObject;

const SystemDescription = modsdf.SystemDescription;

// const SystemDescriptionObject = extern struct {
//     PyObject_HEAD,
//     sdf: SystemDescription,
// };

// const SystemDescriptionType = PyTypeObject{
//     // .ob_base = PyVarObject_HEAD_INIT(null, 0),
//     // TODO: not sure about this name
//     .tp_name = "systemDescription.SystemDescription",
//     .tp_doc = PyDoc_STR("System Description objects"),
//     .tp_basicsize = @sizeOf(SystemDescriptionObject),
// };

var sdf: SystemDescription = undefined;

fn sdfgen_create(_: [*c]PyObject, _: [*c]PyObject) callconv(.C) [*]PyObject {
    sdf = SystemDescription.create(allocator, .aarch64) catch {};

    return Py_BuildValue("i", @as(c_int, 1));
}

fn sdfgen_to_xml(_: [*c]PyObject, _: [*c]PyObject) callconv(.C) [*]PyObject {
    const xml = sdf.toXml() catch "";

    return Py_BuildValue("s", xml.ptr);
}

fn sdfgen_test(_: [*c]PyObject, _: [*c]PyObject) callconv(.C) [*]PyObject {
    return Py_BuildValue("i", @as(c_int, 1));
}

var SdfGenMethods = [_]PyMethodDef{
    PyMethodDef{
        .ml_name = "create",
        .ml_meth = sdfgen_create,
        .ml_flags = METH_NOARGS,
        .ml_doc = "Create",
    },
    PyMethodDef{
        .ml_name = "to_xml",
        .ml_meth = sdfgen_to_xml,
        .ml_flags = METH_NOARGS,
        .ml_doc = "Export to XML string",
    },
    PyMethodDef{
        .ml_name = "test",
        .ml_meth = sdfgen_test,
        .ml_flags = METH_NOARGS,
        .ml_doc = "Testing function of module.",
    },
    // Sentinel
    PyMethodDef{
        .ml_name = null,
        .ml_meth = null,
        .ml_flags = 0,
        .ml_doc = null,
    },
};

var sdfgen_module = PyModuleDef{
    .m_base = PyModuleDef_Base{
        .ob_base = PyObject{
            .ob_refcnt = 1,
            .ob_type = null,
        },
        .m_init = null,
        .m_index = 0,
        .m_copy = null,
    },
    .m_name = "sdfgen",
    .m_doc = null,
    .m_size = -1,
    .m_methods = &SdfGenMethods,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit_sdfgen() [*]PyObject {
    return PyModule_Create(&sdfgen_module);
}
