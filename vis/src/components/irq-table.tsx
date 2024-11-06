import React, { useContext, useEffect, useRef, useState } from 'react'
import { Typography, Checkbox, TableProps, Form, Select, InputNumber, Table, Button, Input } from 'antd'

export interface SysIrq {
  irq: number
  id_: number
  trigger: "edge" | "level"
}

interface SysIrqItem extends SysIrq {
  key: string
  irq_index: number
}

export default function IrqTable({ graph, component, devices }) {
  const [ form ] = Form.useForm()
  const [ data, setData ] = useState([])
  const [ editingKey, setEditingKey ] = useState('')
  const isEditing = (record: SysIrqItem) => record.key === editingKey


  const EditableCell = ({
    editing,
    dataIndex,
    title,
    inputType,
    record,
    index,
    children,
    ...restProps
  }) => {
    const trigger_options = ["edge", "level"]
    const trigger_option_items = trigger_options.map(trigger => {
      return {value: trigger, label: trigger}
    })
    const irq_option_items = devices.map((device, index) => {
      return {value: index, label: device.path}
    })

    const filterOption = (input: string, option?: { label: string; value: string }) =>
    (option?.label ?? '').toLowerCase().includes(input.toLowerCase())

    const inputNodes = {
      'irq': <Select
               showSearch
               placeholder="Select a device"
               optionFilterProp="children"
               filterOption={filterOption}
               options={irq_option_items} />,
      'id': <InputNumber />,
      'trigger': <Select
        showSearch
        placeholder="Select a person"
        optionFilterProp="children"
        filterOption={filterOption}
        options={trigger_option_items} />,
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
                required: true,
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

  const columns = [
    {
      title: 'device',
      dataIndex: 'irq_index',
      width: '35%',
      editable: true,
      dataType: 'irq',
      render: (_: any, record: SysIrqItem) => {
        return <>{devices[record.irq_index].path}</>
      }
    },
    {
      title: 'irq_number',
      dataIndex: 'irq',
      width: '10%',
      dataType: 'number',
      render: (_: any, record: SysIrqItem) => {
        return <>{devices[record.irq_index].irq.irq_number}</>
      }
    },
    {
      title: 'trigger',
      dataIndex: 'trigger',
      width: '15%',
      dataType: 'trigger',
      render: (_: any, record: SysIrqItem) => {
        const trigger = devices[record.irq_index].irq.irq_trigger
        const trigger_str = trigger == 0x01 ? "level" : trigger == 0x04 ? "edge" : "Invalid"
        return <>{trigger_str}</>
      }
    },
    {
      title: 'id',
      dataIndex: 'id_',
      width: '10%',
      editable: true,
      dataType: 'id',
    },
    {
      title: 'operation',
      dataIndex: 'operation',
      render: (_: any, record: SysIrqItem) => {
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
          <Typography.Link disabled={editingKey !== ''} onClick={() => deleteIrq(record.key)}>
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
      onCell: (record: SysIrqItem) => ({
        record,
        inputType: col.dataType,
        dataIndex: col.dataIndex,
        title: col.title,
        editing: isEditing(record),
      }),
    }
  })

  const edit = (record: Partial<SysIrqItem> & { key: React.Key }) => {
    form.setFieldsValue({ ...record });
    setEditingKey(record.key)
  }

  const cancel = () => {
    setEditingKey('')
  }

  const syncNodeData = (newData) => {
    const newIrqs = newData?.map(irq_record => {
      const { key, irq_index , ...rest } = irq_record
      return rest
    })
    component?.updateData(graph, {irqs: newIrqs})
  }

  const handleAdd = () => {
    const newIrq: SysIrqItem = {
      key: data ? data.length.toString() : "0",
      irq: 32,
      id_: 1,
      trigger: "level",
      irq_index: 0
    }

    const newData = [...data, newIrq]
    setData(newData)
    // TODO: update irqs for component
    syncNodeData(newData)
  }

  const save = async (key: React.Key) => {
    try {
      const row = (await form.validateFields()) as SysIrqItem

      const trigger = devices[row.irq_index].irq.irq_trigger
      const trigger_str = trigger == 0x01 ? "level" : "edge"
      row.trigger = trigger_str
      row.irq = devices[row.irq_index].irq.irq_number
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

  const deleteIrq = (key: React.Key) => {
    const newData = data.filter((item) => item.key !== key)
    setData(newData)
    syncNodeData(newData)
  };

  useEffect(() => {
    const originData = component?.getData().irqs.map((irq, index) => {
      const irq_index = devices.indexOf(devices?.find(device => device.irq.irq_number == irq.irq))
      return {...irq, key: index.toString(), irq_index: irq_index}
    })
    setData(originData)
  }, [component])

  return (
    <div>
      <Button onClick={handleAdd} type="primary" style={{ marginBottom: 16 }}>
        Add an IRQ
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
