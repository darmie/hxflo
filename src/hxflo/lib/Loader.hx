package hxflo.lib;

import fbp.Graph;
import hxflo.manifest.Runtime;
import tink.core.Promise;

using tink.CoreApi;

import haxe.io.*;
import sys.*;

typedef Require = composer.Loader;

class Loader {
	public static function registerCustomLoaders(loader:ComponentLoader, componentLoaders:Array<String>):Promise<Dynamic> {
		var f = Future.async(function(cb) {
			if (componentLoaders.length == 0) {
				cb(Failure(null));
				return;
			}
			var customLoader = new Require(componentLoaders.shift()).run();
			loader.registerLoader(customLoader).handle(function(v) {
				if (!v.isSuccess()) {
					cb(Failure(null));
					return;
				}

				registerCustomLoaders(loader, componentLoaders).handle(function(o) {
					if (!o.isSuccess()) {
						cb(Failure(null));
					}
				});
			});
		});

		return f;
	}

	public static function registerModules(loader:ComponentLoader, modules:Array<Dynamic>):Promise<Dynamic> {
		var f = Future.async(function(cb) {
			var componentLoaders:Array<String> = [];
			for (m in modules) {
				loader.setLibraryIcon(m.name, m.icon);

				if (Reflect.hasField(m, "noflo") && m.noflo.loader != null) {
					var loaderPath = Path.join([loader.baseDir, m.base, m.noflo.loader]);
					componentLoaders.push(loaderPath);
				}
				var components:Array<Dynamic> = Reflect.field(m, "components");
				for (c in components) {
					loader.registerComponent(m.name, c.name, Path.join([loader.baseDir, c.path]));
				}
			}

			registerCustomLoaders(loader, componentLoaders).handle(function(o) {
				if (!o.isSuccess()) {
					cb(Failure(null));
				}
			});
		});

		return f;
	}

	public static function register(loader:ComponentLoader):Promise<Dynamic>{
		var f = Future.async(function(cb) {});
		return f;
	}

	public static function dynamicLoad(name:String, cPath:String, metadata:Dynamic):Promise<Dynamic>{
		var f = Future.async(function(cb) {});
		return f;
	}

	public static function setSource(loader:ComponentLoader, packageId:String, name:String, source:String, language:String):Promise<Dynamic> {
		var f = Future.async(function(cb) {});
		return f;		
	}

	public static function getSource(loader:ComponentLoader, name:String):Promise<Dynamic> {
		var f = Future.async(function(cb) {});
		return f;		
	}
}


class ManifestLoader {}

class DynamicLoader {}
