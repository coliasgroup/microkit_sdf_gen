import { Graph } from '@antv/x6'
import { Group } from '../group'
import { SysMapItem } from '../mapping-table'

// Json format for passing configurations to WASM
export interface SystemComponentJsonFormat {}

// Data model of this component
export interface DataModel {
  node_id : string;
  attrs: object;
  subsystem: string | null;
}

export interface EditableAttrs {
    name: string,
    type: 'string' | 'number' | 'boolean' | 'options',
    required: boolean,
    options?: Array<string>,
    min?: number,
    max?: number,
}

export const common_attrs = {
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

export const common_ports = {
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

export const parseMapJson = (mappings: SysMapItem[]) => {
    return mappings.map(map => {
      return {
        ...map,
        perm_r: map.perms.includes('r'),
        perm_w: map.perms.includes('w'),
        perm_x: map.perms.includes('x'),
      }
    })
}

export interface SystemComponentInit {
  preview_attrs: object,
  createNode: (subsystem: string | null, attrs?: any) => Group
}

export interface SystemComponent {
  data : DataModel;
  // Editable attributes, will be shown in Attributes Form
  editable_attrs : Array<EditableAttrs>;

  renderChildrenNodes: (graph: Graph) => void
  renderUnchangableNodes: () => JSX.Element

  getType: () => string
  getData: () => DataModel
  getMappings: () => SysMapItem[]
  getAttrValues: () => object
  
  // Update style if attributes are modified, e.g. PD names
  // Render children nodes if exist
  updateData: (graph: Graph, new_data : object) => void

  // Generate JSON for the component
  getJson: (node?: Group) => object
}
