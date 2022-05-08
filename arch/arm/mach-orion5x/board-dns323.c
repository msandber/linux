// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (C) 2022 Mauri Sandberg <maukka@ext.kapsi.fi>
 *
 * Flattened Device Tree board initialization
 *
 * This is adapted from existing mach files and most of the source code is
 * originally written by:
 *  Copyright (C) 2007 Herbert Valerio Riedel <hvr@gnu.org>
 *  Copyright (C) 2010 Benjamin Herrenschmidt <benh@kernel.crashing.org>
 *  Copyright 2012 (C), Jason Cooper <jason@lakedaemon.net>
 */

#include <linux/of.h>
#include <linux/phy.h>
#include <linux/marvell_phy.h>
#include <linux/of_net.h>
#include <linux/clk.h>
#include "bridge-regs.h"

/* Exposed to userspace, do not change */
enum {
	DNS323_REV_A1,	/* 0 */
	DNS323_REV_B1,	/* 1 */
	DNS323_REV_C1,	/* 2 */
};

/****************************************************************************
 * Fix-ups
 */

static int dns323c_phy_fixup(struct phy_device *phy)
{
	phy->dev_flags |= MARVELL_PHY_M1118_DNS323_LEDS;

	return 0;
}

/****************************************************************************
 * Ethernet
 */

/* dns323_parse_hex_*() taken from tsx09-common.c; should a common copy of these
 * functions be kept somewhere?
 */
static int __init dns323_parse_hex_nibble(char n)
{
	if (n >= '0' && n <= '9')
		return n - '0';

	if (n >= 'A' && n <= 'F')
		return n - 'A' + 10;

	if (n >= 'a' && n <= 'f')
		return n - 'a' + 10;

	return -1;
}

static int __init dns323_parse_hex_byte(const char *b)
{
	int hi;
	int lo;

	hi = dns323_parse_hex_nibble(b[0]);
	lo = dns323_parse_hex_nibble(b[1]);

	if (hi < 0 || lo < 0)
		return -1;

	return (hi << 4) | lo;
}

#define DNS323_NOR_BOOT_BASE 0xf4000000

static int __init dns323_read_mac_addr(u8 *addr)
{
	int i;
	char *mac_page;

	/* MAC address is stored as a regular ol' string in /dev/mtdblock4
	 * (0x007d0000-0x00800000) starting at offset 196480 (0x2ff80).
	 */
	mac_page = ioremap(DNS323_NOR_BOOT_BASE + 0x7d0000 + 196480, 1024);
	if (!mac_page)
		return -ENOMEM;

	/* Sanity check the string we're looking at */
	for (i = 0; i < 5; i++) {
		if (*(mac_page + (i * 3) + 2) != ':')
			goto error_fail;
	}

	for (i = 0; i < ETH_ALEN; i++)	{
		int byte;

		byte = dns323_parse_hex_byte(mac_page + (i * 3));
		if (byte < 0)
			goto error_fail;

		addr[i] = byte;
	}

	iounmap(mac_page);

	return 0;

error_fail:
	iounmap(mac_page);
	return -EINVAL;
}

static void __init dns323_dt_eth_fixup(void)
{
	struct device_node *np;
	u8 addr[ETH_ALEN];
	int ret;

	/*
	 * The ethernet interfaces forget the MAC address assigned by u-boot
	 * if the clocks are turned off. Usually, u-boot on orion boards
	 * has no DT support to properly set local-mac-address property.
	 * As a workaround, we get the MAC address that is stored in flash
	 * and update the port device node if no valid MAC address is set.
	 */
	ret = dns323_read_mac_addr(addr);

	if (ret) {
		pr_warn("Unable to find MAC address in flash memory\n");
		return;
	}

	np = of_find_compatible_node(NULL, NULL, "marvell,orion-eth-port");

	if (!IS_ERR(np)) {
		struct device_node *pnp = of_get_parent(np);
		struct clk *clk;
		struct property *pmac;
		u8 tmpmac[ETH_ALEN];
		u8 *macaddr;
		int i;

		if (!pnp)
			return;

		/* skip disabled nodes or nodes with valid MAC address*/
		if (!of_device_is_available(pnp) ||
		    !of_get_mac_address(np, tmpmac))
			goto eth_fixup_skip;

		clk = of_clk_get(pnp, 0);
		if (IS_ERR(clk))
			goto eth_fixup_skip;

		/* ensure port clock is not gated to not hang CPU */
		clk_prepare_enable(clk);

		/* store MAC address register contents in local-mac-address */
		pmac = kzalloc(sizeof(*pmac) + 6, GFP_KERNEL);
		if (!pmac)
			goto eth_fixup_no_mem;

		pmac->value = pmac + 1;
		pmac->length = ETH_ALEN;
		pmac->name = kstrdup("local-mac-address", GFP_KERNEL);
		if (!pmac->name) {
			kfree(pmac);
			goto eth_fixup_no_mem;
		}

		macaddr = pmac->value;
		for (i = 0; i < ETH_ALEN; i++)
			macaddr[i] = addr[i];

		of_update_property(np, pmac);

eth_fixup_no_mem:
		clk_disable_unprepare(clk);
		clk_put(clk);
eth_fixup_skip:
		of_node_put(pnp);
	}
}

void __init dns323_init_dt(void)
{
	if (of_machine_is_compatible("dlink,dns323a1")) {
		writel(0, MPP_DEV_CTRL);		/* DEV_D[31:16] */
	} else if (of_machine_is_compatible("dlink,dns323c1") &&
		IS_BUILTIN(CONFIG_PHYLIB)) {
		/* Register fixup for the PHY LEDs */
		phy_register_fixup_for_uid(MARVELL_PHY_ID_88E1118,
					   MARVELL_PHY_ID_MASK,
					   dns323c_phy_fixup);

		/* Now, -this- should theorically be done by the sata_mv driver
		 * once I figure out what's going on there. Maybe the behaviour
		 * of the LEDs should be somewhat passed via the platform_data.
		 * for now, just whack the register and make the LEDs happy
		 *
		 * Note: AFAIK, rev B1 needs the same treatement but I'll let
		 * somebody else test it.
		 */
		writel(0x5, ORION5X_SATA_VIRT_BASE + 0x2c);
	}

	dns323_dt_eth_fixup();
}
