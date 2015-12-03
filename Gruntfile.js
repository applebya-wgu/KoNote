/*
Copyright (c) Konode. All rights reserved.
This source code is subject to the terms of the Mozilla Public License, v. 2.0 
that can be found in the LICENSE file or at: http://mozilla.org/MPL/2.0

grunt task for release builds of konote

creates a 'konote-builds' folder beside the project directory containing a mac .dmg and windows .zip

as a final build step on windows, the KoNote.exe icon can be replaced with Resource Hacker:
ResHacker.exe -modify "KoNote.exe", "KoNote.exe", "icon.ico", ICONGROUP, MAINICON, 0

note: requires forked nw-builder module (disables merging win build with the nw exe)
https://github.com/speedskater/node-webkit-builder

it is recommended to build on native OS: building for win from mac/linux will not customize application icon or codesign exe; building for mac from windows/linux will not create dmg installer or codesign .app
*/

// TODO:
// bundle 7zip, resource_hacker, and codesign utility for windows?

var win = null;
var mac = null;
var generic = null;
var griffin = null;

module.exports = function(grunt) {
	grunt.initConfig({
		pkg: grunt.file.readJSON('package.json'),
		
		prompt: {
			platformType: {
				options: {
					questions: [
						{
							config: 'platformType',
							type: 'checkbox',
							message: 'Please select release platform(s)',
							choices: [
								{name: ' Mac', value: 'osx64'},
								{name: ' Windows', value: 'win32'}
							]
						}
					],
					then: function(results) {
						if (results.platformType.indexOf('osx64') !== -1) {
							mac = 1;
						}
						if (results.platformType.indexOf('win32') !== -1) {
							win = 1;
						}
					}
				}
			},
			releaseType: {
				options: {
					questions: [
						{
							config: 'releaseType',
							type: 'checkbox',
							message: 'Please select release type(s)',
							choices: [
								{name: ' Generic', value: 'generic'},
								{name: ' Griffin', value: 'griffin'}
							]
						}
					],
					then: function(results) {
						if (results.releaseType.indexOf('griffin') !== -1) {
							griffin = 1;
						}
						if (results.releaseType.indexOf('generic') !== -1) {
							generic = 1;
						}
					}
				}
			}
		},
		copy: {
			main: {
				files: [
					{
						src: [
							'package.json',
							'src/**',
							'node_modules/**',
							'!node_modules/nw/**',
							'!node_modules/nodewebkit/**
							'!src/config-dev.coffee'
						],
						dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/',
						filter: 'isFile',
						expand: true
					}
				],
				cwd: '/'
			},
			griffin: {
				files: [
					{
						src: [
							'customers/griffin/config-customer.coffee',
							'customer-logo-lg_GRIFFIN.png',
							'customer-logo-sm_GRIFFIN.png'
						],
						dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/'
					}
				]
			},
			generic: {
				files: [
					{
						src: [
							'build/uninstaller/uninstall.exe'
						],
						dest: 'build/releases/temp/<%= grunt.task.current.args[0] %>/uninstall.exe'
					}
				]
			}
		},
		
		
		// downloads nwjs binaries and bundles w project
		nwjs: {
			mac: {
				options: {
					appName: '<%= pkg.displayName %>',
					//macCredits: 'path-to-file',
					macIcns: 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/icon.icns',
					version: '<%= pkg.dependencies.nodewebkit %>', //nwjs version to download
					platforms: ['osx64'],
					buildType: 'default',
					buildDir: 'build/releases/temp/nwjs/<%= grunt.task.current.args[0] %>',
					cacheDir: 'build/releases/temp/cache/<%= grunt.task.current.args[0] %>',
					macZip: false,
					forceDownload: true
				},
				src: ['build/releases/temp/<%= grunt.task.current.args[0] %>/**']
			},
			win: {
				options: {
					appName: '<%= pkg.displayName %>',
					version: '<%= pkg.dependencies.nodewebkit %>', //nwjs version to download
					platforms: ['win32'],
					buildType: 'default',
					buildDir: 'build/releases/temp/nwjs/<%= grunt.task.current.args[0] %>',
					cacheDir: 'build/releases/temp/cache/<%= grunt.task.current.args[0] %>',
					winZip: false,
					forceDownload: true
				},
				src: ['build/releases/temp/<%= grunt.task.current.args[0] %>/**']
			}
    	},
		// format the osx folder icon for the dmg, zip windows build, cleanup tmp files
		exec: {
			prep: "mv ../konote-releases/temp/<%= grunt.task.current.args[0] %>/KoNote/osx64 ../konote-releases/temp/<%= grunt.task.current.args[0] %>/KoNote",
			append: "Rez -append icon.rsrc -o ../konote-releases/temp/<%= grunt.task.current.args[0] %>/KoNote/$'Icon\r'",
			set: "SetFile -a C ../konote-releases/temp/<%= grunt.task.current.args[0] %>/KoNote",
			hide: "SetFile -a V $'../konote-releases/temp/<%= grunt.task.current.args[0] %>/KoNote/Icon\r'",
			zip: {
				cwd: 'build/releases/temp/<%= grunt.task.current.args[0] %>/KoNote/win32',
				cmd: 'zip -r --quiet ../../../../konote-<%= pkg.version %>-<%= grunt.task.current.args[0] %>.zip *'
			},
			//cleanCoffee: "rm -rf builds/releases/temp/<%= grunt.task.current.args[0] %>/*.coffee",
			clean: 'rm -rf build/releases/temp'
		},
		// build pretty .dmg
		appdmg: {
			main: {
				options: {
					basepath: './',
					title: 'KoNote-<%= pkg.version %>',
					icon: 'icon.icns',
					background: 'background.tiff', 'icon-size': 104,
					contents: [
						{x: 130, y: 150, type: 'file', path: 'build/releases/temp/<%= grunt.task.current.args[0] %>/KoNote/osx64/KoNote.app'},
						{x: 320, y: 150, type: 'link', path: '/Applications'}
					]
				},
				dest: 'build/releases/konote-<%= pkg.version %>-<%= grunt.task.current.args[0] %>.dmg'
			}
		},
		stylus: {
			compile: {
				files: {
					'build/releases/temp/<%= grunt.task.current.args[0] %>/src/main.css': 'build/releases/temp/<%= grunt.task.current.args[0] %>/src/main.styl'
				}
			}
		},
		coffee: {
			compileWithMaps: {
				options: {
					sourceMap: true
				},
				files: {
					'path/to/result.js': 'path/to/source.coffee'
				}
			},
			compileMultiple: {
				expand: true,
				cwd: 'build/releases/temp/<%= grunt.task.current.args[0] %>/',
				src: ['**/*.coffee'],
				dest: 'src/',
				ext: '.js'
			}
		}
	});
	
	// load the plugins
	grunt.loadNpmTasks('grunt-nw-builder');
	grunt.loadNpmTasks('grunt-exec');
	grunt.loadNpmTasks('grunt-contrib-copy');
	grunt.loadNpmTasks('grunt-prompt');
	grunt.loadNpmTasks('grunt-contrib-stylus');
	grunt.loadNpmTasks('grunt-contrib-coffee');
	
	// if on osx, we can use appdmg
	if (process.platform == 'darwin') {
		grunt.loadNpmTasks('grunt-appdmg');
	}
	
	grunt.registerTask('build', function() {
			grunt.task.run('prompt');
			grunt.task.run('release')
	});
	
	grunt.registerTask('release', function() {
		
		grunt.task.run('exec:clean');
		
		if (win) {
			if (generic) {
				// do win generic build
				grunt.task.run('copy:main:win-generic');
				grunt.task.run('copy:generic:win-generic');
				grunt.task.run('stylus:compile:win-generic');
				grunt.task.run('coffee:compileMultiple:win-generic');
				//grunt.task.run('exec:cleanCoffee:win-generic');
				grunt.task.run('nwjs:win:win-generic');
				grunt.task.run('exec:zip:win-generic');
			}
			if (griffin) {
				// do win griffin build
				grunt.task.run('copy:main:win-griffin');
				grunt.task.run('copy:griffin:win-griffin');
				grunt.task.run('stylus:compile:win-griffin');
				grunt.task.run('coffee:compileMultiple:win-generic');
				grunt.task.run('nwjs:win:win-griffin');
				grunt.task.run('exec:zip:win-griffin');
			}
		}
		if (mac) {
			if (generic) {
				// do mac generic build
				grunt.task.run('copy:main:mac-generic');
				grunt.task.run('stylus:compile:mac-generic');
				grunt.task.run('coffee:compileMultiple:win-generic');
				//grunt.task.run('copy:osx:mac-generic');
				grunt.task.run('nwjs:mac:mac-generic');
				//grunt.task.run('exec:prep:mac-generic');
				//grunt.task.run('exec:append:mac-generic');
				//grunt.task.run('exec:set:mac-generic');
				//grunt.task.run('exec:hide:mac-generic');
				if (process.platform == 'darwin') {
					grunt.task.run('appdmg:main:mac-generic');
				}
			}
			if (griffin) {
				// do mac griffin build
				grunt.task.run('copy:main:mac-griffin');
				grunt.task.run('stylus:compile:mac-generic');
				grunt.task.run('coffee:compileMultiple:win-generic');
				grunt.task.run('nwjs:mac:mac-griffin');
				//grunt.task.run('exec:prep:mac-griffin');
				//grunt.task.run('exec:append:mac-griffin');
				//grunt.task.run('exec:set:mac-griffin');
				//grunt.task.run('exec:hide:mac-griffin');
				if (process.platform == 'darwin') {
					grunt.task.run('appdmg:main:mac-griffin');
				}
			}
		}
		grunt.task.run('exec:clean');
	});
	
};
