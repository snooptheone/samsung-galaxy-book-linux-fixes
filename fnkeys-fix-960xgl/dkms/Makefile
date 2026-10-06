obj-m := samsung-galaxybook.o
KVER ?= $(shell uname -r)
KDIR := /lib/modules/$(KVER)/build
EXTRA_CFLAGS += -I$(src)
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
