`ifndef INC_LOG_H
`define INC_LOG_H

`define LOGI(msg) $display("[I|%0t|%m] %s", $time, msg)
`define LOGW(msg) $display("[W|%0t|%m] %s", $time, msg)
`define LOGE(msg) $display("[E|%0t|%m] %s", $time, msg)

`endif
