package;

import hxflo.manifest.Runtime;

class Test {
    public static function main(){
        Runtime.listComponents(Sys.getCwd()+"/test/components", {
            root: Sys.getCwd(),
            subdirs: true
        }).handle(function(c){
            trace(c.getParameters()[0]);
        });
    }
}