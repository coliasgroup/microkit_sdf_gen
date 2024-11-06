import { Graph, Cell, Edge } from '@antv/x6'
import { Group } from '../components/group'
import { XMLParser } from 'fast-xml-parser'
import { MemoryRegion, SysMap, SysIrq } from './element'
import { PDComponentInit } from '../components/os-components/pd'
import { VMComponentInit } from '../components/os-components/vm'

const layoutInfo = (nodes) => {
  const min_x_gap = 400
  const min_y_gap = 200
  const grid = []

  const row = Math.ceil(Math.sqrt(nodes.length))
  for (let i = 1; i <= row; i++) {
    for (let j = 1; j <= row; j++) {
      grid.push({x: i * min_x_gap, y: j * min_y_gap})
    }
  }
  return grid
}

const parseMappings = (json_mappings: any) => {
  // parse mappings
  if (json_mappings == null) {
    json_mappings = []
  }
  if (Array.isArray(json_mappings) == false) {
    json_mappings = [json_mappings]
  }

  const mappings = json_mappings.map(mapping => {
    const newMapping: SysMap = {
      mr: mapping.mr,
      vaddr: parseInt(mapping.vaddr.replace("_", ""), 16),
      setvar_vaddr: mapping.setvar_vaddr,
      perms: mapping.perms,
      cached: (mapping.cached && mapping.cached == "true") ? true : false,
    }
    return newMapping
  })
  return mappings
}

const parseIrqs = (json_irqs: any) => {
    // parse irqs
    if (json_irqs == null) {
      json_irqs = []
    }
    if (Array.isArray(json_irqs) == false) {
      json_irqs = [json_irqs]
    }

  const irqs = json_irqs?.map(irq => {
    const newIrq: SysIrq = {
      irq: irq.irq,
      id_: parseInt(irq.id),
      trigger: irq.trigger
    }
    return newIrq
  })

  return irqs;
}

const parseVm = (json_vm: any) => {
  if (json_vm == null) return null

  console.log(json_vm)
  const new_vm_attrs = {
    name: json_vm.name,
    id_: json_vm.id,
    priority: parseInt(json_vm.priority),
    budget: json_vm.budget ? parseInt(json_vm.budget) : 0,
    period: json_vm.period ? parseInt(json_vm.period) : 0,
  }

  return {
    attrs: new_vm_attrs,
    mappings: parseMappings(json_vm.map),
    irqs: parseIrqs(json_vm.irq),
  }
}

const parsePds = (graph: Graph, json_pds: any[]) => {
  const pds = json_pds.map(json_pd => {
    // TODO: extend to a data type, PDDataModel in `pd.tsx` or ProtectionDomain in `element.tsx`
    const new_pd_attrs = {
      name: json_pd.name,
      priority: parseInt(json_pd.priority),
      budget: json_pd.budget ? parseInt(json_pd.budget) : 0,
      period: json_pd.period ? parseInt(json_pd.period) : 0,
      pp: (json_pd.pp && json_pd.pp == "true") ? true : false,
      prog_img: json_pd.program_image.path
    }

    return {
      attrs: new_pd_attrs,
      mappings: parseMappings(json_pd.map),
      irqs: parseIrqs(json_pd.irq),
      vm: parseVm(json_pd.virtual_machine)
    }
  })

  return pds
}

export const loadDiagramFromXml = (graph: Graph, xml: string, updateMappings: any) => {
  const parser = new XMLParser({ignoreAttributes: false, attributeNamePrefix : ""})
  const system_description = parser.parse(xml).system
  console.log(system_description)

  const pds = parsePds(graph, system_description.protection_domain ?? [])

  const grid = layoutInfo(pds)
  const nodes = pds.map((pd, index) => {
    const { vm, ...data } = pd
    const new_node = PDComponentInit.createNode(null)
    new_node.position(grid[index].x, grid[index].y)
    graph.addNode(new_node)

    if (vm) {
      const vm_node = VMComponentInit.createNode(null)
      new_node.addChild(vm_node)
      vm_node.position(20, 30, { relative: true })
      vm_node.data.component.updateData(graph, vm)
    }

    new_node.data.component.updateData(graph, data)
    return new_node
  })

  const edges = system_description.channel?.map(channel => {
    const source = nodes.find(node => node.data.component.getAttrValues().name == channel.end[0].pd)
    const source_end_id = parseInt(channel.end[0].id)
    const target = nodes.find(node => node.data.component.getAttrValues().name == channel.end[1].pd)
    const target_end_id = parseInt(channel.end[1].id)
    const edge = graph.addEdge({
      source,
      target,
      router: {
        name: 'manhattan'
      }
    })
    edge.attr('line/targetMarker', { tagName: 'circle', r: 2 })
    edge.attr('line/sourceMarker', { tagName: 'circle', r: 2 })
    edge.data = {
      type: 'channel',
      source_node: source,
      source_end_id: source_end_id,
      target_node: target,
      target_end_id: target_end_id,
    }
    return edge
  })

  // Parse MRs
  const MRs = system_description.memory_region?.map(mr => {
    const newMR: MemoryRegion = {
      name: mr.name,
      size: parseInt(mr.size.replace("_", ""), 16),
      phys_addr: mr.phys_addr ? parseInt(mr.phys_addr.replace("_", ""), 16) : null,
      page_size: mr.page_size ? parseInt(mr.page_size.replace("_", ""), 16) : null,
      nodes: []
    }
    return newMR
  })
  updateMappings(MRs)
}
