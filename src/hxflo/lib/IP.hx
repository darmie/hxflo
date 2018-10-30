/**
 * HxFlo - Flow-Based Programming for Haxe
 * (c) 2018-present Damilare Akinlaja, Nigeria
 * (c) 2013-2017 Flowhub UG
 *
 * HxFlo may be freely distributed under the MIT license
 */

package hxflo.lib;

using hxflo.lib.BasePort;



typedef TIP = {
    var type:String,
    var data:Dynamic,
    var _isIP:Dynamic,
    var scope:String,
    var owner:Dynamic,
    var clonable:Bool,
    var index:Int,
    var schema:Dynamic,
    var datatype:ValidTypes,
    var types:Array<String>,
    var initial:Bool
}


/**
 * Information Packets
 * 
 * IP objects are the way information is transmitted between
 * components running in a NoFlo network. IP objects contain
 * a `type` that defines whether they're regular `data` IPs
 * or whether they are the beginning or end of a stream
 * (`openBracket`, `closeBracket`).
 * 
 * The component currently holding an IP object is identified
 * with the `owner` key.
 * 
 * By default, IP objects may be sent to multiple components.
 * If they're set to be clonable, each component will receive
 * its own clone of the IP. This should be enabled for any
 * IP object working with data that is safe to clone.
 * 
 * 
 * It is also possible to carry metadata with an IP object.
 * For example, the `datatype` and `schema` of the sending
 * port is transmitted with the IP object.
 */

@:forward(
    type,
    data,
    _isIP,
    scope,
    owner,
    clonable,
    index,
    schema,
    datatype,
    types,
    initial
)
abstract IP(TIP) from TIP to TIP {

	/**
	 * Creates as new IP object
     * 
     * Valid types: 'data', 'openBracket', 'closeBracket'
     * 
	 * @param type 
	 * @param data 
	 * @param options 
	 */
	public inline function new(type:String, data:Dynamic = null, options:Dynamic = null) {
		this = {
			type: type,
			data: data,
			_isIP: true,
			scope: null, // sync scope id
			owner: null, // packet owner process
			clonable: false, // cloning safety flag
			index: null, // addressable port index
			schema: null,
			datatype: ValidTypes.ALL,
            initial: false,
			types: ['data','openBracket','closeBracket']
		};

		for (field in Reflect.fields(options)) {
			Reflect.setField(this, field, Reflect.field(this, field));
		}
	}

	/**
	 * Detects if an arbitrary value is an IP
	 * @param payload 
	 * @return Bool
	 */
	public inline static function isIP(payload:Dynamic):Bool {
		return Reflect.isObject(payload) && payload._isIP == true;
	}

    /**
     * Creates a new IP copying its contents by value not reference
     * @return IP
     */
    public inline function clone():IP{
        var ip:IP = new IP(this.type);
        for(field in Reflect.fields(this)){
            if (['owner'].indexOf(field) != -1) {
                continue;
            }
            if(Reflect.field(this, field) == null){
                continue;
            }

            var val = Reflect.field(this, field);
            Reflect.setField(ip, field, val);
        }

        return ip;
    }

    /**
     * Moves an IP to a different owner
     * @param owner 
     */
    public inline function move(owner:Dynamic){
        this.owner = owner;
    }

    /**
     * Frees IP contents
     */
    public inline function drop(){
        for(field in Reflect.fields(this)){
            Reflect.deleteField(this, field);
        }
    }
}
