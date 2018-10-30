package hxflo.manifest;

import haxe.io.*;
import sys.*;
import tink.core.Promise;

using tink.CoreApi;
using StringTools;

class Runtime {
	private static function parseId(source:String, filePath:String):String {
		var nameReg:EReg = ~/@name ([A-Za-z0-9]+)/;
		var id:String;

		if (nameReg.match(source)) {
			id = nameReg.matched(1);
			return id;
		}

		return hx.files.Path.of(filePath).filename;
	}

	private static function parseRuntime(source:String, filePath:String):String {
		var nameReg:EReg = ~/@runtime ([A-Za-z0-9]+)/;
		var id:String;

		if (nameReg.match(source)) {
			id = nameReg.matched(1);
			return id;
		}

		return hx.files.Path.of(filePath).filename;
	}

	public static function listComponents(componentDir:String, options:Dynamic):Promise<Dynamic> {
		var f = Future.async(function(cb) {
			var entries = FileSystem.readDirectory(componentDir);

			var potential = entries.filter(function(c) {
				var needle = Path.extension(c);
				for (s in ["hscript", "hx"]) {
					if (needle == s) {
						return true;
					}
				}
				return false;
			});

			var components = potential.filter(function(p) {
				var componentPath = Path.join([componentDir, p]);
				return hx.files.Path.of(componentPath).isFile();
			}).map(function(p) {
					var componentPath = Path.join([componentDir, p]);
					var component = {
						name: null,
						path: componentPath,
						source: componentPath,
						elementary: true,
						runtime: "hxflo"
					};

					var source = sys.io.File.getContent(componentPath);
					component.name = parseId(source, componentPath);
					component.runtime = parseRuntime(source, componentPath);
					return component;
				});

			var potentialDirs = entries.filter(function(entry) return potential.indexOf(entry) == -1);

			if (potentialDirs.length == 0) {
				return cb(Success(components));
			}
			if (options.subdirs == false) {
				return cb(Success(components));
			}

			var directories = potentialDirs.filter(function(d) {
				var dirPath = FileSystem.fullPath(Path.join([componentDir, d]));
				return hx.files.Path.of(dirPath).isDirectory();
			});

			var subDirs = directories.map(function(d) {
				var dirPath = FileSystem.fullPath(Path.join([componentDir, d]));
				return listComponents(dirPath, options);
			});

			for (subComponents in subDirs) {
				subComponents.handle(function(c) {
					components = components.concat(c.getParameters()[0]);
				});
			}

			return cb(Success(components));
		});

		return f;
	}

	public static function listGraphs(componentDir:String, options:Dynamic):Promise<Dynamic> {
		var f = Future.async(function(cb) {
			var entries = FileSystem.readDirectory(componentDir);

			var potential = entries.filter(function(c) {
				var needle = Path.extension(c);
				for (s in ["fbp", "json"]) {
					if (needle == s) {
						return true;
					}
				}
				return false;
			});

			var components = potential.filter(function(p) {
				var componentPath = Path.join([componentDir, p]);
				return hx.files.Path.of(componentPath).isFile();
			}).map(function(p) {
					var componentPath = Path.join([componentDir, p]);
					var component = {
						name: null,
						path: componentPath,
						source: componentPath,
						elementary: false,
						runtime: "hxflo"
					};

					var source = sys.io.File.getContent(componentPath);
					if (Path.extension(component.path) == 'fbp') {
						component.name = parseId(source, componentPath);
						component.runtime = parseRuntime(source, componentPath);
						return component;
					} 

					var graph = haxe.Json.parse(source);
					component.name = (graph.properties != null ? graph.properties.id : null) == null ?  parseId(source, componentPath) : graph.properties.id;
					if (graph.properties != null ? graph.properties.main : null) {
						if (Reflect.hasField(component, "noflo")) { 
							// component.noflo = {};
							Reflect.setField(component, "noflo", {}); 
						}
						Reflect.setField(Reflect.field(component, "noflo"), "main", graph.properties.main); 
					}

					return component;
				});

			return cb(Success(components));
		});

		return f;
	}


	public static function getModuleInfo(baseDir:String, options:Dynamic):Promise<Dynamic> {
		return null;
	}

	public static function listDependencies(baseDir:String, options:Dynamic):Promise<Dynamic> {
		return null;
	}
}
