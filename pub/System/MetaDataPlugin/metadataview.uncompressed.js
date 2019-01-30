/*
 * MetaData View
 *
 * Copyright (c) 2011-2019 Michael Daum http://michaeldaumconsulting.com
 *
 * Dual licensed under the MIT and GPL licenses:
 *   http://www.opensource.org/licenses/mit-license.php
 *   http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function($) {

  var defaults = {
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
  }

  // show actions 
  MetaDataView.prototype.showActions = function($row) {
    var self = this;

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
        return;
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
    }).on("click", ".metaDataEditAction", function() {
      var $this = $(this),
          tr = $this.parents("tr:first"),
          next = tr.next(),
          prev = tr.prev();

      if (prev.find(".metaDataActions").length) {
        $this.data("metadata::prev", "#"+prev.find(".metaDataEditAction").attr("id"));
      } else {
        $this.data("metadata::prev", undefined);
      }
      if (next.find(".metaDataActions").length) {
        $this.data("metadata::next", "#"+next.find(".metaDataEditAction").attr("id"));
      } else {
        $this.data("metadata::next", undefined);
      }
    });
  };

  // register to jquery
  $.fn.metaDataView = function (opts) { 
    return this.each(function() { 
      if (!$.data(this, "metaDataView")) { 
        $.data(this, "metaDataView", 
          new MetaDataView(this, opts)); 
        } 
    }); 
  };
 
  // document ready things
  $(function() {
    $(".metaDataView").livequery(function() {
      var $this = $(this),
          opts = $.extend({}, $this.metadata({type:'elem', name:'script'}));

      $this.metaDataView(opts);
    });
  });

  $.validator.addClassRules("foswikiMandatory", {
    required: true
  });

})(jQuery);
