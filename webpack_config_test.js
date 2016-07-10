// Generated by LiveScript 1.5.0
(function(){
  var path, process, livescript, RewirePlugin, cwd, npmdir, fromcwd, webpack_config;
  path = require('path');
  process = require('process');
  livescript = require('livescript');
  RewirePlugin = require('rewire-webpack');
  cwd = process.cwd();
  npmdir = function(x){
    return path.join(cwd, 'node_modules', x);
  };
  fromcwd = function(x){
    return path.join(cwd, x);
  };
  webpack_config = require('./webpack_config.ls');
  webpack_config.module.loaders = [{
    test: /\.ls$/,
    loader: 'livescript-loader',
    include: [fromcwd('test'), fromcwd('src')],
    exclude: [fromcwd('src/components_skate'), fromcwd('node_modules'), fromcwd('bower_components')]
  }];
  webpack_config.plugins.push(new RewirePlugin());
  module.exports = webpack_config;
}).call(this);