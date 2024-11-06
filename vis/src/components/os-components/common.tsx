import { Graph } from "@antv/x6"

export interface EditableAttrs {
  name: string,
  type: 'string' | 'number' | 'boolean',
  required: boolean,
  min?: number,
  max?: number,
}

const common_attrs = {
  ports: {
    groups: {
      bottom: {
        position: 'bottom',
        attrs: {
          circle: {
            magnet: true,
            stroke: '#8f8f8f',
            r: 5,
          },
        },
      },
    },
  },
}

const common_ports = {
  ports: {
    groups: {
      top: {
        position: 'top',
        attrs: {
          circle: {
            magnet: true,
            stroke: '#8f8f8f',
            r: 0,
          },
        },
      },
      left: {
        position: 'left',
        attrs: {
          circle: {
            magnet: true,
            stroke: '#8f8f8f',
            r: 0,
          },
        },
      },
      right: {
        position: 'right',
        attrs: {
          circle: {
            magnet: true,
            stroke: '#8f8f8f',
            r: 0,
          },
        },
      },
      bottom: {
        position: 'bottom',
        attrs: {
          circle: {
            magnet: true,
            stroke: '#8f8f8f',
            r: 0,
          },
        },
      },
    },
  }
}

const addChannel = (graph : Graph, sourceNode, targetNode) => {
  const edge = graph.addEdge({
    source: sourceNode,
    target: targetNode
  })
  edge.attr('line/targetMarker', { tagName: 'circle', r: 2 })
  edge.attr('line/sourceMarker', { tagName: 'circle', r: 2 })
  edge.data = { 
    type: 'channel',
    source_node: sourceNode,
    source_end_id: '1',
    target_node: targetNode,
    target_end_id: '1',
  }
}

export { common_attrs, common_ports, addChannel }