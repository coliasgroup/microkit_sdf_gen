import React from 'react';
import { JsonViewer } from '@textea/json-viewer'

// Json-viewer: https://github.com/TexteaInc/json-viewer

const DeviceTreeViewer = ({ deviceTreeJson }) => {

  return (
    <>
      <JsonViewer value={deviceTreeJson} displayDataTypes={false} />
    </>
  )
}

export default DeviceTreeViewer
