import { useEffect, useState  } from 'react'
import { Modal, Form, InputNumber, Input } from 'antd'

export default function ChannelEditor({ graph, channelEditorOpen, setChannelEditorOpen, edge_id, getEdgeData, updateEdgeData, getNodeData }) {
  const [ form ] = Form.useForm(null)
  const [ data, setData ] = useState(null)
  const [ sourceName, setSourceName ] = useState('')
  const [ targetName, setTargetName ] = useState('')

  const saveEdge = () => {
    updateEdgeData(edge_id, form.getFieldsValue())
    setChannelEditorOpen(false)
  }

  useEffect(() => {
    const edge = graph?.getCellById(edge_id)
    if (edge) {
      setData(edge.data)
      console.log(edge.data)
      setSourceName(edge.data.source_node.data.component.getAttrValues().name)
      setTargetName(edge.data.target_node.data.component.getAttrValues().name)
    }
    form.setFieldsValue(data)
  })

  return (
    <Modal
      title="Edit communication channel"
      centered
      open={channelEditorOpen}
      forceRender
      onOk={saveEdge}
      onCancel={(e) => {e.stopPropagation();setChannelEditorOpen(false)}}
    >
      <Form
        name="channel-editor"
        form={ form }
        wrapperCol={{ span: 16 }}
        style={{ maxWidth: 600 }}
        initialValues={ data }
        layout="vertical"
        onFinish={saveEdge}
        autoComplete="off"
      >
        <Form.Item
          label=""
          name="source_node"
          rules={[{ required: true }]}
          hidden={true}
        >
          <Input />
        </Form.Item>
        <Form.Item
          label={sourceName + "-end_id"}
          name="source_end_id"
          rules={[{ required: true }]}
        >
          <InputNumber min={1} max={256} />
        </Form.Item>
        <Form.Item
          label=""
          name="target_node"
          rules={[{ required: true }]}
          hidden={true}
        >
          <Input />
        </Form.Item>
        <Form.Item
          label={targetName + "-end_id"}
          name="target_end_id"
          rules={[{ required: true }]}
        >
          <InputNumber min={1} max={256} />
        </Form.Item>
      </Form>
    </Modal>
  )
}
