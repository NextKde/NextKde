pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
QtObject {
    id: client
    function request(operation, payload, callback) {
        worker.createObject(client, {operation: operation, payload: payload, callback: callback})
    }
    property Component worker: Component {
        Process {
            id: process
            required property string operation
            required property var payload
            required property var callback
            command: ["node", "-e", "const fs=require('fs'),path=require('path');const [op,raw]=process.argv.slice(1),p=JSON.parse(raw),file=path.join(process.env.KOS_NOTIFICATION_TEST_STATE_ROOT,p.dir,p.file);if(op==='state.read'){console.log(JSON.stringify({ok:true,result:{exists:fs.existsSync(file),data:fs.existsSync(file)?fs.readFileSync(file,'utf8'):''}}))}else{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,p.data);console.log(JSON.stringify({ok:true,result:{}}))}", operation, JSON.stringify(payload)]
            stdout: StdioCollector { onStreamFinished: process.callback(JSON.parse(text)) }
            onExited: process.destroy()
            Component.onCompleted: running = true
        }
    }
}
