dispatcher_add(function(sammy) {
    sammy.get('#/itc_bd', function() {
            render({'itc_bd': '/itc_bd' ,
                     'vhosts': '/vhosts'},
                   'itc_bd', '#/itc_bd');
        });
  /*  sammy.get('#itc_bd/:from/:to/:file',function(){
     var path = '/itc_bd/' + esc(this.params['from']) + '/' + esc(this.params['to'])+'/'
      + esc(this.params['file']);
     render({'itc': path},
        'itc_bd', '#/itc_bd');
    });*/
    sammy.put('#/itc_bd', function() {
            if (sync_put(this, '/itc_bd/:vhost/:from/:to/:file'))
                update();
            return false;
        });

});

NAVIGATION['Admin'][0]['ITC'] = ['#/itc_bd', 'administrator'];

