/**
 * HxFlo - Flow-Based Programming for Haxe
 * (c) 2018-present Damilare Akinlaja, Nigeria
 * (c) 2013-2017 Flowhub UG
 * (c) 2011-2012 Henri Bergius, Nemein
 *
 * HxFlo may be freely distributed under the MIT license
 */
package hxflo.lib;

import fbp.Graph;

using StringTools;
using tink.CoreApi;

/**
 * The HxFlo Component Loader
 *
 * The Component Loader is responsible for discovering components
 * available in the running system, as well as for instantiating
 * them.
 *
 * Internally the loader uses a registered loader. Hxflo ships
 * with a loader for hscript that discovers components from the
 * current project's `components/` and `graphs/` folders, as
 * well as those folders of any installed Haxe dependencies.
 *
 */
class ComponentLoader extends EventEmitter {
	public var baseDir:String;
	public var options:Dynamic;
	public var components:haxe.DynamicAccess<Dynamic>;
	public var libraryIcons:haxe.DynamicAccess<Dynamic>;
	public var processing:Bool;
	public var ready:Bool;

	public function new(baseDir:String, ?options:Dynamic) {
		super();

		this.baseDir = baseDir;
		this.options = options != null ? options : {};
		this.components = null;
		this.libraryIcons = {};

		this.processing = false;
		this.ready = false;
	}

	/**
	 * Get the library prefix for a given module name. This
	 * is mostly used for generating valid names for namespaced
	 * component modules, as well as for convenience renaming all
	 * `hxflo-` prefixed modules with just their base name.
	 *
	 * Example:
	 *
	 * `my-project` becomes `my-project`
	 * `@foo/my-project` becomes `my-project`
	 * `hxflo-core` becomes `core`
	 *
	 * @param name
	 * @return String
	 */
	public function getModulePrefix(name:String):String {
		if (name == 'hxflo')
			return '';

		var nameReg:EReg = ~/@[a-z\-]+\//;
		if (name.charAt(0) == '@')
			return nameReg.replace(name, '');

		nameReg = ~/^hxflo-/;
		return nameReg.replace(name, '');
	}

	/**
	 * Get the list of all available components
	 * @return Promise<Dynamic>
	 */
	public function listComponents():Promise<Dynamic> {
		var f = Future.async(function(cb) {
			if (this.processing) {
				once('ready', new EventCallback(function(args) {
					cb(Success(this.components));
				}));

				return;
			}

			if (this.components != null) {
				cb(Success(this.components));
			}

			this.ready = false;
			this.processing = true;

			this.components = {};

			Loader.register(this).handle(function(o) {
				if (!o.isSuccess()) {
					cb(Failure(null));
				}
				this.processing = false;
				this.ready = true;
				emit('ready', [true]);
				cb(Success(this.components));
			});
		});

		return f;
	}

	/**
	 * Load an instance of a specific component. If the
	 * registered component is a JSON or FBP graph, it will
	 * be loaded as an instance of the hxFlo subgraph
	 * component.
	 * @param name
	 * @param metadata
	 * @return Promise<Dynamic>
	 */
	public function load(name:String, metadata:Dynamic):Promise<Dynamic> {
		var f = Future.async(function(cb) {
			if (!ready) {
				this.listComponents().handle(function(o) {
					if (!o.isSuccess()) {
						cb(Failure(null));
					}
					load(name, metadata).handle(function(o) {
						if (!o.isSuccess()) {
							cb(Failure(null));
						}
					});
				});
				cb(Success(null));
				return;
			}

			var component:Dynamic = this.components[name];
			if (component == null) {
				// Try an alias
				for (componentName in components.keys()) {
					if (componentName.split('/')[1] == name) {
						component = components[componentName];
						break;
					}
				}

				if (component == null) {
					// Failure to load
					cb(Failure('Component ${name} not available with base ${}'));
					return;
				}

				if (isGraph(component)) {
					loadGraph(name, component, metadata);
					return;
				}

				createComponent(name, component, metadata).handle(function(res) {
					if (res.isSuccess()) {
						var instance:Component = res.getParameters()[0];
						if (instance == null) {
							cb(Failure('Component ${name} could not be loaded'));
						}

						if (name == 'Graph') {
							instance.baseDir = baseDir;
						}
						instance.componentName = name;
						setIcon(name, instance);
						cb(Success(instance));
					} else {
						cb(Failure('Component ${name} could not be loaded'));
					}
				});
			}
		});

		return f;
	}

	/**
	 * Check if a given filesystem path is actually a graph
	 * @param component
	 * @return Bool
	 */
	public function isGraph(cPath:Dynamic):Bool {
		// Live graph instance
		if (Std.is(cPath, fbp.Graph)) {
			return true;
		}
		// Graph JSON definition
		if (Reflect.hasField(cPath, "processes") || Reflect.hasField(cPath, "connections")) {
			return true;
		}

		if (!Std.is(cPath, String)) {
			return false;
		} else {
			// Graph file path
			return cPath.indexOf('.fbp') != -1 || cPath.indexOf('.json') != -1;
		}
	}

	/**
	 * Load a graph as a hxFlo subgraph component instance
	 * @param name
	 * @param component
	 * @param metadata
	 * @return Promise<Dynamic>
	 */
	public function loadGraph(name:String, component:Dynamic, metadata:Dynamic):Promise<Dynamic> {
		var f = Future.async(function(cb) {
			createComponent(name, components['Graph'], metadata).handle(function(res) {
				if (res.isSuccess()) {
					var graph = res.getParameters()[0];
					graph.loader = this;
					graph.baseDir = baseDir;
					graph.inPorts.remove('graph');
					graph.setGraph(component).handle(function(o) {
						if (o.isSuccess()) {
							setIcon(name, graph);
							cb(Success(graph));
						} else {
							cb(Failure(null));
						}
					}) return;
				} else {
					cb(Failure(null));
					return;
				}
			});
		});

		return f;
	}

	/**
	 * Creates an instance of a component.
	 * @param name
	 * @param component
	 * @param metadata
	 * @return Promise<Dynamic>
	 */
	public function createComponent(name:String, component:Dynamic, metadata:Dynamic):Promise<Dynamic> {
		var f = Future.async(function(cb) {
			var implementation:Dynamic = component;
			if (implementation == null) {
				cb(Failure('Component ${name} not available'));
			}

			// If a string was specified, attempt to `require` it.
			if (Std.is(implementation, String)) {
				Loader.dynamicLoad(name, implementation, metadata).handle(function(o) {
					if (o.isSuccess()) {
						var instance = o.getParameters()[0];
						cb(Success(instance));
					}
				}) return;
			} else {
				try {
					var instance;
					// Attempt to create the component instance using the `getComponent` method.
					if (Reflect.hasField(Type.getClass(implementation), 'getComponent')) {
						instance = implementation.getComponent(metadata)
					} else if (Reflect.isFunction(implementation)) {
						instance = implementation(metadata);
					}
					cb(Success(instance));
				} catch (e:Dynamic) {
					cb(Failure(e));
				}

				return;
			}
		});

		return f;
	}

	/**
	 * Set icon for the component instance. If the instance
	 * has an icon set, then this is a no-op. Otherwise we
	 * determine an icon based on the module it is coming
	 * from, or use a fallback icon separately for subgraphs
	 * and elementary components.
	 *
	 * @param name
	 * @param instance
	 */
	public function setIcon(name:String, instance:Dynamic) {
		// See if component has an icon
		if (!Reflect.hasField(Type.getClass(instance), "getIcon") && instance.getIcon() != null) {
			return;
		}

		// See if library has an icon
		var c = name.split('/');
		var library = c[0];
		var componentName = c[1];
		if (componentName != null && getLibraryIcon(library) != null) {
			instance.setIcon(getLibraryIcon(library));
			return;
		}

		// See if instance is a subgraph
		if (instance.subGraph() != null) {
			instance.setIcon('sitemap');
			return;
		}

		instance.setIcon('gear');
	}

	public function getLibraryIcon(lib:String) {
		if (libraryIcons[lib]) {
			return libraryIcons[lib];
		}

		return null;
	}

	public function setLibraryIcon(prefix:String, icon:String) {
		this.libraryIcons[prefix] = icon;
	}

	public function normalizeName(packageId:String, name:String) {
		var prefix = getModulePrefix(packageId);

		var fullName = '${prefix}/${name}';

		if (packageId == null) {
			fullName = name;
		}

		return fullName;
	}

	/**
	 * Registering components at runtime
	 *
	 * In addition to components discovered by the loader,
	 * it is possible to register components at runtime.
	 *
	 * With the `registerComponent` method you can register
	 * a hxFlo Component constructor or factory method
	 * as a component available for loading.
	 *
	 *
	 * @param packageId
	 * @param name
	 * @param cPath
	 * @return Promise<Dynamic>
	 */
	public function registerComponent(packageId:String, name:String, cPath:String):Promise<Dynamic> {
		var f = Future.async(function(cb) {
			var fullName = normalizeName(packageId, name);
			components[fullName] = cPath;
			cb(Success(null));
		});
		return f;
	}

	/**
	 * With the `registerGraph` method you can register new
	 * graphs as loadable components.
	 *
	 * @param packageId
	 * @param name
	 * @param gPath
	 * @return Promise<Dynamic>
	 */
	public function registerGraph(packageId:String, name:String, gPath:String):Promise<Dynamic> {
		return registerComponent(packageId, name, gPath);
	}

	/**
	 * With `registerLoader` you can register custom component
	 * loaders. They will be called immediately and can register
	 * any components or graphs they wish.
	 *
	 * @param loader
	 * @return Promise<Dynamic>
	 */
	public function registerLoader(loader:ComponentLoader->Promise<Dynamic>):Promise<Dynamic> {
		return loader(this);
	}

	/**
	 * With `setSource` you can register a component by providing
	 * a source code string. Supported languages and techniques
	 * depend on the runtime environment, for example hscript
	 * components can only be registered via `setSource` if
	 * the environment has hscript enabled
	 *
	 *
	 * @param packageId
	 * @param name
	 * @param source
	 * @param language
	 * @return Promise<Dynamic>
	 */
	public function setSource(packageId:String, name:String, source:String, language:String):Promise<Dynamic> {
		var f = Future.async(function(cb) {
			if (!ready) {
				listComponents().handle(function(o) {
					if (!o.isSuccess()) {
						cb(Failure(null));
						return;
					}

					setSource(packageId, name, source, language).handle(function(o) {
						if (!o.isSuccess()) {
							cb(Failure(null));
							return;
						}
					});
					return;
				});
				return;
			}

			Loader.setSource(this, packageId, name, source, language);
			cb(Success(null));
		});
		return f;
	}

	public function getSource(name):Promise<Dynamic> {
		var f = Future.async(function(cb) {
			if (!ready) {
				listComponents().handle(function(o) {
					if (!o.isSuccess()) {
						cb(Failure(null));
						return;
					}

					getSource(name).handle(function(o) {
						if (!o.isSuccess()) {
							cb(Failure(null));
							return;
						}
					});
					return;
				});
				return;
			}

			Loader.getSource(this, name);
			cb(Success(null));
		});
		return f;		
	}

	public function clear(){
		components = null;
		ready = false;
		processing = false;
	}
}
