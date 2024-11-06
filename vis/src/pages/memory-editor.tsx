import React, { useContext, useEffect, useRef, useState } from 'react'
import { Typography, Checkbox, TableProps, Form, Select, InputNumber, Table, Button, Input } from 'antd'
import { MemoryRegion, SysMap } from '../utils/element'


interface MemoryRegionItem extends MemoryRegion {
  key: string
  size_str: string
  phys_addr_str?: string
}

export const MemoryEditor = ({ MRs, setMRs, pageSizeOptions }) => {
  const [form] = Form.useForm()
  const [editingKey, setEditingKey] = useState('')
  const [data, setData] = useState<MemoryRegionItem[]>(null)
  const isEditing = (record: MemoryRegionItem) => record.key === editingKey

  const page_size_options = pageSizeOptions?.map(page_size => {
    return { label: `${page_size.label} (0x${page_size.value.toString(16)})`, value: page_size.value }
  })

  const EditableCell = ({
    editing,
    dataIndex,
    title,
    inputType,
    required,
    record,
    index,
    children,
    ...restProps
  }) =>{
    const perm_options = ['r', 'w', 'x']


    const inputNodes = {
      'number': <InputNumber />,
      'select': <Select
        showSearch
        placeholder="Default page size"
        optionFilterProp="children"
        options={page_size_options} />,
      'boolean': <Checkbox />,
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

  const edit = (record: Partial<MemoryRegionItem> & { key: React.Key }) => {
    form.setFieldsValue({ ...record });
    setEditingKey(record.key)
  }

  const deleteMR = (key: React.Key) => {
    const newMRs = [...MRs]
    const index = data.findIndex((item) => key === item.key)
    newMRs.splice(index, 1)
    setMRs(newMRs)
  };

  const cancel = () => {
    setEditingKey('')
  }

  const save = async (editing_key: React.Key) => {
    try {
      const row = (await form.validateFields()) as MemoryRegionItem

      row.size = parseInt(row.size_str, 16)
      row.phys_addr = row.phys_addr_str ? parseInt(row.phys_addr_str, 16) : null

      console.log(row.page_size)
      const { key, phys_addr_str, size_str, ...newMR } = row
      const newMRs = [...MRs]
      const index = data.findIndex((item) => editing_key === item.key)
      if (index > -1) {
        const item = MRs[index]
        newMRs.splice(index, 1, {
          ...item,
          ...newMR,
        })
        setEditingKey('')
      } else {
        newMRs.push(newMR)
        setEditingKey('')
      }

      console.log(newMRs)
      setMRs(newMRs)
    } catch (errInfo) {
      console.log('Validate Failed:', errInfo)
    }
  }

  const handleAdd = () => {
    const newMR : MemoryRegion = {
      name: `default`,
      size: 0,
      page_size: null,
      nodes: [],
    }
    setMRs([...MRs, newMR])
  }

  const columns = [
    {
      title: 'name *',
      dataIndex: 'name',
      width: '20%',
      editable: true,
      dataType: 'string',
      required: true,
    },
    {
      title: 'size *',
      dataIndex: 'size_str',
      width: '20%',
      editable: true,
      dataType: 'string',
      required: true,
    },
    {
      title: 'phys_addr',
      dataIndex: 'phys_addr_str',
      width: '20%',
      editable: true,
      dataType: 'string',
      required: false,
    },
    {
      title: 'page_size',
      dataIndex: 'page_size',
      width: '25%',
      editable: true,
      dataType: 'select',
      required: false,
      render: (_: any, record: MemoryRegionItem) => {
        const page_size = page_size_options.find(page_size => record.page_size == page_size.value)
        if (page_size == null) {
          return <></>
        }

        return <>{page_size.label}</>
      }
    },
    {
      title: 'operation',
      dataIndex: 'operation',
      render: (_: any, record: MemoryRegionItem) => {
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
          <Typography.Link disabled={editingKey !== ''} onClick={() => deleteMR(record.key)}>
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
      onCell: (record: MemoryRegionItem) => ({
        record,
        inputType: col.dataType,
        dataIndex: col.dataIndex,
        title: col.title,
        editing: isEditing(record),
        required: col.required,
      }),
    }
  })

  useEffect(() => {
    console.log(MRs)
    const newData : MemoryRegionItem[] = MRs.map((MR, index) => {
      return {
        ...MR,
        key: index.toString(),
        phys_addr_str: MR.phys_addr ? '0x' + (MR.phys_addr).toString(16) : null,
        size_str: '0x' + (MR.size).toString(16)
      }
    })
    setData(newData)
  }, [MRs])

  return (
    <div>
      <Button onClick={handleAdd} type="primary" style={{ marginBottom: 16 }}>
        New Memory Region
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
