import { FunctionComponent, useEffect } from 'react'
import { InputNumber, Form, Input, Button, Checkbox } from 'antd'
import { SystemComponent } from './os-components/component-interface'
import { Graph } from '@antv/x6'

export const getFormItem = (attr) => {
  const inputType = attr?.type
  const attrName = attr?.name

  const inputNodes = {
    'number': <InputNumber min={attr?.min} max={attr?.max} />,
    'boolean': <Checkbox />,
    'string': <Input />
  }
  const inputNode = inputNodes[inputType]

  return (
    <Form.Item
      label={attrName}
      name={attrName}
      rules={[{ required: attr?.required }]}
      valuePropName={inputType === 'boolean' ? 'checked' : 'value'}
      key={attrName}
    >
      {inputNode}
    </Form.Item>
  )
}

interface AttrsFromPros {
  graph: Graph;
  setNodeEditorOpen: Function;
  component: SystemComponent;
}

export const AttrsForm: FunctionComponent<AttrsFromPros> = ({ graph, setNodeEditorOpen, component }) => {
  const node_attrs = component?.getData().attrs

  const editable_attrs = component?.editable_attrs
  const [ form ] = Form.useForm(null)

  const saveNodeData = (data : any) => {
    let new_data = {...node_attrs}

    Object.keys(new_data).forEach(key => {
      new_data[key] = data[key]
    })

    component.updateData(graph, { attrs: new_data })

    setNodeEditorOpen(false)
  }

  useEffect(() => {
    form.setFieldsValue(node_attrs)
  })

  return (
    <>
      {component?.renderUnchangableNodes()}
      <Form
        name="basic"
        form={ form }
        wrapperCol={{ span: 16 }}
        style={{ maxWidth: 600 }}
        initialValues={ node_attrs }
        layout="vertical"
        onFinish={saveNodeData}
        autoComplete="off"
      >
        {editable_attrs?.map(attr => {
          return getFormItem(attr)
        })
        }
        <Button htmlType="submit" type="primary">
          Save
        </Button>
        <Button htmlType="button" style={{ margin: '0 8px' }} onClick={() => setNodeEditorOpen(false)}>
          Cancel
        </Button>
      </Form>
    </>
  )
}
