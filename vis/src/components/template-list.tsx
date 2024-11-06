import { Modal, Table } from 'antd'
import type { TableColumnsType } from 'antd';

interface DataType {
  key: React.Key;
  name: string;
  type: string;
  content: string;
}

export default function TemplateList({ templateListOpen, setTemplateListOpen, graph }) {

  const toTemplateList = () => {

    // TODO: fix it up
    const PDs = [] // graph?.getCells().filter(cell => cell.data.type === 'PD')
    return PDs?.map(PD => {
      const edges = graph.getEdges()
      const channels = edges?.map(edge => {
        if (edge.getSourceNode().id == PD.id) {
          const targetName = edge.getTargetNode()?.data.attrs.name
          return {"name": targetName, "end_id": edge.data.source_end_id}
        } else if (edge.getTargetNode().id == PD.id) {
          const sourceName = edge.getSourceNode()?.data.attrs.name
          return {"name": sourceName, "end_id": edge.data.target_end_id}
        }
        return
      })?.filter(entry => entry != null)

      const channels_definition = channels.map(channel => "#define " + channel.name + " " + channel.end_id)
      const content = "#pragma once\n\n" + channels_definition?.join("\n")

      return {
        key: PD.id + 'cheaderfile',
        name: PD.data.attrs.name + '.h',
        type: 'C Header File',
        content: content,
      }
    })
  }

  const columns : TableColumnsType<DataType> = [
    {
      title: 'File Name',
      dataIndex: 'name',
    },
    {
      title: 'Type',
      dataIndex: 'type',
    },
    {
      title: 'Operation',
      dataIndex: 'content',
      render: (text: string, record: DataType) => <a onClick={() => downloadFile(record.name, text)}>Download</a>,
    },
  ]

  const data = [
    {
      key: '1',
      name: 'pd1.h',
      type: 'C Header File',
      content: 'content',
    },
    {
      key: '2',
      name: 'pd2.h',
      type: 'C Header File',
      content: 'content',
    },
    {
      key: '3',
      name: 'pd3.h',
      type: 'C Header File',
      content: 'content',
    },
  ]

  const downloadFile = async (filename, content) => {
    // Create a writable stream to the user's filesystem
    try {
      const fileHandle = await window.showSaveFilePicker({
        suggestedName: filename
      });
  
      const writableStream = await fileHandle.createWritable();
      await writableStream.write(content);
      await writableStream.close();
    } catch (error) {
      console.log(error)
    }
  };

  return (
    <Modal
      title="Template Files"
      centered
      forceRender
      open={templateListOpen}
      onOk={() => setTemplateListOpen(false)}
      onCancel={() => setTemplateListOpen(false)}
      width={1000}
    >
      <div>
      <Table
        columns={columns}
        dataSource={toTemplateList()}
      />
      </div>
    </Modal>
  )
}
