require 'test_common'

require 'tc_aggs'
require 'tc_attr_rewrite'
# require 'tc_bust'
require 'tc_callback'
require 'tc_channel'
require 'tc_collections'
require 'tc_dbm'
require 'tc_delta'
require 'tc_errors'
require 'tc_exists'
require 'tc_foreground'
# require 'tc_forkdeploy'
require 'tc_inheritance'
require 'tc_interface'
require 'tc_joins'
require 'tc_mapvariants'
require 'tc_meta'
require 'tc_metrics'
require 'tc_module'
require 'tc_nest'
require 'tc_new_executor'
# require 'tc_rebl'
require 'tc_schemafree'
require 'tc_semistructured'
# errors in tc_temp best resolved by a new parser?
require 'tc_temp'
require 'tc_terminal'
require 'tc_timer'
# require 'tc_threaddeploy'
require 'tc_wc'

if defined? Bud::HAVE_TOKYOCABINET
  require 'tc_tc'
end
