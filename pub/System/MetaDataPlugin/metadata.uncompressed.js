"use strict";
(function($) {

  // global defaults
  var 
    pluginName = 'metaDataView',
    pluginClass = '.metaDataView',
    defaults = {
      hideActionDelay: 1500
    };


  // class constructor
  function MetaDataView(elem, opts) {
    var self = this;

    self.elem = $(elem);
    self.opts = $.extend({}, defaults, opts);

    //console.log("called new");

    self.init();

    return self;
  };

  // show actions 
  MetaDataView.prototype.showActions = function($row) {
    var self = this, 
        $actions = $row.find(".metaDataActions");

    self.elem.find(".hover").removeClass("hover");
    $row.addClass("hover");
  };

  // hide actions 
  MetaDataView.prototype.hideActions = function() {
    var self = this;

    self.elem.find(".hover").removeClass("hover");
  };

  // adds a hide-action timer
  MetaDataView.prototype.startTimer = function() {
    var self = this;
    self.timeout = setTimeout(function() {
      if (!self.active) {
        self.hideActions();
      }
    }, self.opts.hideActionDelay);
  };

  // init method
  MetaDataView.prototype.init = function() {
    var self = this;
    
    self.active = false;

    self.elem.find(".metaDataActions").hover(
      function() {
        self.active = true;
      },
      function() {
        self.active = false;
        self.startTimer();
      }
    );

    self.elem.on("mouseenter", ".metaDataRow, tbody tr", function() {
      var $row = $(this), 
          $actions = $row.find(".metaDataActions");

      if ($actions.length) {
        self.active = true;
        if (self.timeout) {
          clearTimeout(self.timeout);
        }
        self.showActions($row);
      }
    }).on("mouseleave", ".metaDataRow, tbody tr", function() {
      self.active = false;
      self.startTimer();
    }).on("click", ".metaDataRow, tbody tr", function(e) {
      var $this = $(this), 
          $editAction = $this.find(".metaDataEditAction");

      if (self.elem.is(".metaDataReadOnly")) {
        return
      }

      $this.effect("highlight");

      if ($(e.target).is(".metaDataRow, td")) {
        self.elem.find("tr").removeClass("selected");
        $this.addClass("selected");

        if ($editAction.length) {
          $editAction.trigger("click");
          return false;
        }
      }
    });
  };

  // register to jquery
  $.fn[pluginName] = function (opts) { 
    return this.each(function() { 
      if (!$.data(this, pluginName)) { 
        $.data(this, pluginName, 
          new MetaDataView(this, opts)); 
        } 
    }); 
  };
 
  // document ready things
  $(function() {
    $(pluginClass).livequery(function() {
      var $this = $(this),
          opts = $.extend({}, $this.metadata({type:'elem', name:'script'}));

      $this[pluginName](opts);
    });
  });

})(jQuery);
