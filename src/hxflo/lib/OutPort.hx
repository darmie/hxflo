/**
 * HxFlo - Flow-Based Programming for Haxe
 * (c) 2018-present Damilare Akinlaja, Nigeria
 * (c) 2013-2017 Flowhub UG
 *
 * HxFlo may be freely distributed under the MIT license
 */
package hxflo.lib;

import haxe.ds.IntMap;

using hxflo.lib.BasePort;

/**
 * HxFlo outport
 *
 * Input Port (outport) implementation for NoFlo components. These
 * ports are the way a component receives Information Packets.
 */
class OutPort extends BasePort {
	public var cache:IntMap<Dynamic>;

	public function new(?options:Dynamic) {
		if (Reflect.hasField(options, "scoped")) {
			options.scoped = true;
		}
		super(options);

		cache = new IntMap<Dynamic>();
	}

	override public function attach(socket:InternalSocket, index:Int = null) {
		super.attach(socket, index);

		if (isCaching() && cache.get(index) != null) {
			send(cache.get(index), index);
		}
	}

	public function connect(socketId:Int = null) {
		var sockets:Array<InternalSocket> = getSockets(socketId);
		checkRequired(sockets);

		for (socket in sockets) {
			if (socket == null) {
				continue;
			}
			socket.connect();
		}
	}

	public function beginGroup(group:Dynamic, socketId:Int = null) {
		var sockets:Array<InternalSocket> = getSockets(socketId);
		checkRequired(sockets);

		for (socket in sockets) {
			if (socket == null) {
				continue;
			}
			socket.beginGroup(group);
		}
	}

	public function send(data:Dynamic, socketId:Int = null) {
		var sockets:Array<InternalSocket> = getSockets(socketId);
		checkRequired(sockets);

		if (isCaching() && data != cache.get(socketId)) {
			cache.set(socketId, data);
		}

		for (socket in sockets) {
			if (socket == null) {
				continue;
			}
			socket.send(data);
		}
	}

	public function endGroup(socketId:Int = null) {
		var sockets:Array<InternalSocket> = getSockets(socketId);
		checkRequired(sockets);

		for (socket in sockets) {
			if (socket == null) {
				continue;
			}
			socket.endGroup();
		}
	}

	public function disconnect(socketId:Int = null) {
		var sockets:Array<InternalSocket> = getSockets(socketId);
		checkRequired(sockets);

		for (socket in sockets) {
			if (socket == null) {
				continue;
			}
			socket.disconnect();
		}
	}

	public function sendIP(type:Dynamic, data:Dynamic, options:Dynamic, socketId:Int, autoConnect:Bool = true):OutPort {
		var ip:IP = null;
		if (IP.isIP(type)) {
			ip = type;
			socketId = ip.index;
		} else {
			ip = new IP(type, data, options);
		}

		var sockets:Array<InternalSocket> = getSockets(socketId);
		checkRequired(sockets);

		if (ip.datatype == ValidTypes.ALL) {
			// Stamp non-specific IP objects with port datatype
			ip.datatype = getDataType();
		}

		if (getSchema() != null && ip.schema == null) {
			// Stamp non-specific IP objects with port schema
			ip.schema = getSchema();
		}

		if (isCaching() && data != cache.get(socketId).data) {
			cache.set(socketId, ip);
		}

		var pristine = true;

		for (socket in sockets) {
			if (socket == null) {
				continue;
			}
            if(pristine){
                socket.post(ip, autoConnect);
                pristine = false;
            } else {
                ip = ip.clonable ? ip.clone() : ip;
                socket.post(ip, autoConnect);
            }
		}

        return this;
	}

    public function openBracket(data:Dynamic = null, options:Dynamic, socketId:Int = null){
        return sendIP('openBracket', data, options, socketId);
    }

    public function data(data:Dynamic = null, options:Dynamic, socketId:Int = null) {
        return sendIP('data', data, options, socketId);
    }

    public function closeBracket(data:Dynamic = null, options:Dynamic, socketId:Int = null){
        return sendIP('closeBracket', data, options, socketId);
    }

    public function checkRequired(sockets:Array<InternalSocket>){
        if(sockets.length == 0 && isRequired()){
            throw '${@getId()}: No connections available';
        }
    }

    public function getSockets(socketId:Int):Array<InternalSocket>{
        // Addressable sockets affect only one connection at time
        if (isAddressable()){
            if(socketId == null){
                throw '${@getId()} Socket ID required';
            }
            if(this.sockets[socketId] == null){
                return [];
            }

            return [this.sockets[socketId]];
        }

        // Regular sockets affect all outbound connections
        return this.sockets;
    }

    public function isCaching(){
        if(options.caching){
            return true;
        }

        return false;
    }
}




