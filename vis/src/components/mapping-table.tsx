import React, { useContext, useEffect, useRef, useState } from 'react'
import { Typography, Checkbox, TableProps, Form, Select, InputNumber, Table, Button, Input } from 'antd'
import { SysMap } from '../utils/element'

export interface SysMapItem extends SysMap {
  key: string
  vaddr_str: string
}

export default function MappingTable({ graph, MRs, component, updateMappings }) {
  const [form] = Form.useForm()
  const [editingKey, setEditingKey] = useState('')
  const [data, setData] = useState<SysMapItem[]>([])
  const isEditing = (record: SysMapItem) => record.key === editingKey

  const EditableCell = ({
    editing,
    dataIndex,
    title,
    required,
    inputType,
    record,
    index,
    children,
    ...restProps
  }) => {
    const perm_options = ['r', 'w', 'x']

    const mr_options = MRs.map(MR => {
      return { value: MR.name, label: MR.name }
    })
    const filterOption = (input: string, option?: { label: string; value: string }) =>
    (option?.label ?? '').toLowerCase().includes(input.toLowerCase())

    const inputNodes = {
      'number': <InputNumber />,
      'select': <Select
        showSearch
        placeholder="Select a person"
        optionFilterProp="children"
        filterOption={filterOption}
        options={mr_options} />,
      'boolean': <Checkbox />,
      'multichoice': <Checkbox.Group options={perm_options}/>,
      'string': <Input />
    }
    const inputNode = inputNodes[inputType]
  
    return (
      <td {...restProps}>
        {editing ? (
          <Form.Item
            name={dataIndex}
            style={{ margin: 0 }}
            rules={[
              {
                required: required,
                message: `Please Input ${title}!`,
              },
            ]}
            valuePropName={inputType === 'boolean' ? 'checked' : 'value'}
          >
            {inputNode}
          </Form.Item>
        ) : (
          children
        )}
      </td>
    )
  }

  const edit = (record: Partial<SysMapItem> & { key: React.Key }) => {
    form.setFieldsValue({ ...record });
    setEditingKey(record.key)
  }

  const deleteMapping = (key: React.Key) => {
    const newData = data.filter((item) => item.key !== key)
    setData(newData)
    syncNodeData(newData)
  };

  const cancel = () => {
    setEditingKey('')
  }

  const syncNodeData = (newData) => {
    // TODO: component provide interface for updating mappings
    const newMappings = newData?.map(mapping => {
      const { key, ...rest } = mapping
      return rest
    })
    component?.updateData(graph, {mappings: newMappings})
    updateMappings()
  }

  const save = async (key: React.Key) => {
    try {
      const row = (await form.validateFields()) as SysMapItem

      row.vaddr = parseInt(row.vaddr_str, 16)
      if (row.setvar_vaddr == "") {
        row.setvar_vaddr = null
      }
      const newData = [...data]
      const index = newData.findIndex((item) => key === item.key)
      if (index > -1) {
        const item = newData[index]
        newData.splice(index, 1, {
          ...item,
          ...row,
        });
        setData(newData)
        setEditingKey('')
      } else {
        newData.push(row)
        setData(newData)
        setEditingKey('')
      }

      syncNodeData(newData)
    } catch (errInfo) {
      console.log('Validate Failed:', errInfo)
    }
  }

  const handleAdd = () => {
    const newMapping: SysMapItem = {
      key: data ? data.length.toString() : '0',
      mr: `default`,
      vaddr: 0,
      vaddr_str: '0x0',
      perms: 'rw',
      cached: false,
      setvar_vaddr: ``
    }

    const newData = [...data, newMapping]
    setData(newData)
    syncNodeData(newData)
  }

  const columns = [
    {
      title: 'mr',
      dataIndex: 'mr',
      width: '20%',
      editable: true,
      required: true,
      dataType: 'select',
    },
    {
      title: 'perms',
      dataIndex: 'perms',
      width: '5%',
      editable: true,
      required: true,
      dataType: 'multichoice',
    },
    {
      title: 'vaddr',
      dataIndex: 'vaddr_str',
      width: '20%',
      editable: true,
      required: true,
      dataType: 'string',
    },
    {
      title: 'setvar_vaddr',
      dataIndex: 'setvar_vaddr',
      width: '20%',
      editable: true,
      required: false,
      dataType: 'string',
    },
    {
      title: 'cached',
      dataIndex: 'cached',
      width: '5%',
      editable: true,
      required: true,
      dataType: 'boolean',
      render: (_: any, record: SysMapItem) => {
        return <Checkbox defaultChecked={record.cached} disabled={true} />
      }
    },
    {
      title: 'operation',
      dataIndex: 'operation',
      render: (_: any, record: SysMapItem) => {
        const editable = isEditing(record);
        return editable ? (
          <span>
            <Typography.Link onClick={() => save(record.key)} style={{ marginRight: 8 }}>
              Save
            </Typography.Link>
            <Typography.Link onClick={cancel}>
              Cancel
            </Typography.Link>
          </span>
        ) : (
          <span>
          <Typography.Link disabled={editingKey !== ''} onClick={() => edit(record)} style={{ marginRight: 8 }}>
            Edit
          </Typography.Link>
          <Typography.Link disabled={editingKey !== ''} onClick={() => deleteMapping(record.key)}>
            Delete
          </Typography.Link>
          </span>
        )
      },
    },
  ]

  const mergedColumns: TableProps['columns'] = columns.map((col) => {
    if (!col.editable) {
      return col
    }
    return {
      ...col,
      onCell: (record: SysMapItem) => ({
        record,
        inputType: col.dataType,
        dataIndex: col.dataIndex,
        title: col.title,
        required: col.required,
        editing: isEditing(record),
      }),
    }
  })

  useEffect(() => {
    const originData = component?.getData().mappings.map((mapping, index) => {
      const vaddr_str = '0x' + mapping.vaddr.toString(16)
      return {...mapping, key: index.toString(), vaddr_str: vaddr_str}
    })
    setData(originData)
  }, [component])

  return (
    <div>
      <Button onClick={handleAdd} type="primary" style={{ marginBottom: 16 }}>
        Add a mapping
      </Button>
      <Form form={form} component={false}>
        <Table
          components={{
            body: {
              cell: EditableCell,
            },
          }}
          bordered
          dataSource={data}
          columns={mergedColumns}
          rowClassName="editable-row"
          pagination={{
            onChange: cancel,
          }}
        />
      </Form>
    </div>
  )
}
