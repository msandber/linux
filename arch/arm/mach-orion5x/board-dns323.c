// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (C) 2022 Mauri Sandberg <maukka@ext.kapsi.fi>
 *
 * Flattened Device Tree board initialization
 *
 * This is adapted from existing mach file and most of the source code is
 * originally written by:
 *  Copyright (C) 2007 Herbert Valerio Riedel <hvr@gnu.org>
 *  Copyright (C) 2010 Benjamin Herrenschmidt <benh@kernel.crashing.org>
 */

#include <linux/of.h>
#include <linux/phy.h>
#include <linux/marvell_phy.h>
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
}
