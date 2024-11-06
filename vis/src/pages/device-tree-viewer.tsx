import React, { useState, useEffect } from 'react';
import init, {greet} from "validator-wasm"
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
