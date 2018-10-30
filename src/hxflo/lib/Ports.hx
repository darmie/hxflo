/**
 * HxFlo - Flow-Based Programming for Haxe
 * (c) 2018-present Damilare Akinlaja, Nigeria
 * (c) 2014-2017 Flowhub UG
 *
 * HxFlo may be freely distributed under the MIT license
 */
package hxflo.lib;

import haxe.ds.StringMap;

/**
 * HxFlo ports collections
 *
 * Ports collection classes for NoFlo components. These are
 * used to hold a set of input or output ports of a component.
 */
class Ports extends EventEmitter {
	public var model:BasePort;
	public var ports:Dynamic;

	public function new(ports:Dynamic) {
		super();
		this.ports = new StringMap<BasePort>();
	
		if (ports == null) {
			throw "ports cannot be null";
		}

		for (name in Reflect.fields(ports)) {
			add(name, Reflect.field(ports, name));
		}
	}

	public function add(name:String, options:Dynamic) {
		if (name == 'add' || name == 'remove') {
			throw "'add' and 'remove' are restricted port names";
		}

		var nameReg = ~/^[a-z0-9_\.\/]+$/;
		if (nameReg.match(name)) {
			throw 'Port names can only contain lowercase alphanumeric characters and underscores. ${name} not allowed';
		}

		// Remove previous implementation
		if (Reflect.hasField(ports,name)) {
			remove(name);
		}

		if (Reflect.isObject(options) && options.canAttach) {
			Reflect.setField(ports, name, options);
		} else {
			if (Std.is(this, InPorts)) {
				model = new InPort(options);
			} else if (Std.is(this, OutPorts)) {
				model = new OutPort(options);
			}
			Reflect.setField(ports, name, model);
		}

		Reflect.setField(Type.getClass(this), name, Reflect.field(ports, name));

		emit('add', [name]);

		return this;
	}

	public function remove(name:String) {
		if (!Reflect.hasField(ports,name))
			throw 'Port ${name} not defined';

		Reflect.deleteField(ports, name);
		Reflect.deleteField(Type.getClass(this), name);
		emit('remove', [name]);

		return this;
	}

	/**
	 * Port name normalization:
	 * 
	 * returns object containing keys name and index for ports names in
	 * format `portname` or `portname[index]`.
	 * @param name 
	 */
	public static inline function normalizePortName(name:String):Dynamic {
		var port = {
			name: name,
			index: 0
		};

		// Regular port
		if(name.indexOf('[') == -1){
			return port;
		}

		// Addressable port with index
		var nameReg:EReg = ~/(.*)\[([0-9]+)\]/;
        
        if(!nameReg.match(name)){
            return name;
        }

		port.name = nameReg.matched(1);
		port.index = Std.parseInt(nameReg.matched(2));
        

		return port;
	}
}

class InPorts extends Ports {
	public function On(name:String, event:String, callback:EventCallback) {
		if (!Reflect.hasField(ports,name))
			throw 'Port ${name} not available';
        cast(Reflect.field(ports,name), InPort).on(event, callback);
	}

	public function Once(name:String, event:String, callback:EventCallback) {
		if (!Reflect.hasField(ports,name))
			throw 'Port ${name} not available';
        cast(Reflect.field(ports, name), InPort).once(event, callback);
	}
}

class OutPorts extends Ports {

    public function connect(name:String, socketId:Int = null){
		if (!Reflect.hasField(ports,name))
			throw 'Port ${name} not available';
        cast(Reflect.field(ports,name), OutPort).connect(socketId);        
    }

    public function beginGroup(name:String, group:Dynamic, socketId:Int = null){
		if (!Reflect.hasField(ports,name))
			throw 'Port ${name} not available';
        cast(Reflect.field(ports,name), OutPort).beginGroup(group, socketId);        
    }

    public function endGroup(name:String, socketId:Int = null){
		if (!Reflect.hasField(ports,name))
			throw 'Port ${name} not available';
        cast(Reflect.field(ports,name), OutPort).endGroup(socketId);        
    }

    public function disconnect(name:String, socketId:Int = null){
		if (!Reflect.hasField(ports,name))
			throw 'Port ${name} not available';
        cast(Reflect.field(ports,name), OutPort).disconnect(socketId);        
    }    
}
