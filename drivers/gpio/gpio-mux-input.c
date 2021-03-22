// SPDX-License-Identifier: GPL-2.0-only
/*
 *  A 4-ways input multiplexer GPIO driver
 *
 *  Copyright (C) 2010 Gabor Juhos <juhosg@openwrt.org>
 *  Copyright (C) 2020 Mauri Sandberg <sandberg@mailfence.com>
 *
 */

#include <linux/version.h>
#include <linux/module.h>
#include <linux/init.h>
#include <linux/gpio/consumer.h>
#include <linux/gpio/driver.h>
#include <linux/slab.h>
#include <linux/platform_device.h>

#include <linux/mux/consumer.h>

#define DRIVER_NAME	"gpio-mux-input""

struct gpio_mux_input_chip {
	struct device		*parent;
	struct gpio_chip	gpio_chip;
	struct mux_control	*mux_control;
	struct gpio_desc	*mux_pin;
};

static struct gpio_mux_input_chip *gpio_to_mux(struct gpio_chip *gc)
{
	return container_of(gc, struct gpio_mux_input_chip, gpio_chip);
}

static int gpio_mux_input_direction_input(struct gpio_chip *gc,
				       unsigned int offset)
{
	return 0;
}

static int gpio_mux_input_direction_output(struct gpio_chip *gc,
					unsigned int offset, int val)
{
	return -EINVAL;
}

static int gpio_mux_input_get_value(struct gpio_chip *gc, unsigned int offset)
{
	struct gpio_mux_input_chip *mux;
	struct gpio_mux_input_platform_data *pdata;
	int ret;

	mux = gpio_to_mux(gc);
	pdata = mux->parent->platform_data;

	ret = mux_control_select(mux->mux_control, offset);
	if (ret)
		return ret;

	ret = gpiod_get_value(mux->mux_pin);
	mux_control_deselect(mux->mux_control);
	return ret;
}

static void gpio_mux_input_set_value(struct gpio_chip *gc,
				  unsigned int offset, int val)
{
	/* not supported */
}

static int gpio_mux_input_probe(struct platform_device *pdev)
{
	struct device_node *np = pdev->dev.of_node;
	struct gpio_mux_input_chip *mux;
	struct gpio_chip *gc;
	struct mux_control *mc;
	struct gpio_desc *pin;
	int err;

	mux = kzalloc(sizeof(struct gpio_mux_input_chip), GFP_KERNEL);
	if (mux == NULL)
		return -ENOMEM;

	mc = mux_control_get(&pdev->dev, NULL);
	if (IS_ERR(mc)) {
		err = (int) PTR_ERR(mc);
		if (err != -EPROBE_DEFER)
			dev_err(&pdev->dev, "unable to get mux: %d\n", err);
		goto err_free_mux;
	}

	mux->mux_control = mc;
	pin = gpiod_get(&pdev->dev, "pin",  GPIOD_IN);
	if (IS_ERR(pin)) {
		err = (int) PTR_ERR(pin);
		dev_err(&pdev->dev, "unable to claim pin GPIO: %d\n", err);
		goto err_free_mc;
	}

	mux->mux_pin = pin;
	mux->parent = &pdev->dev;

	gc = &mux->gpio_chip;
	gc->direction_input  = gpio_mux_input_direction_input;
	gc->direction_output = gpio_mux_input_direction_output;
	gc->get = gpio_mux_input_get_value;
	gc->set = gpio_mux_input_set_value;
	gc->can_sleep = 1;

	gc->base = -1;
	gc->ngpio = mux_control_states(mc);
	gc->label = dev_name(mux->parent);
	gc->parent = mux->parent;
	gc->owner = THIS_MODULE;
	gc->of_node = np;

	err = gpiochip_add(&mux->gpio_chip);
	if (err) {
		dev_err(&pdev->dev, "unable to add gpio chip, err=%d\n", err);
		goto err_free_pin;
	}

	platform_set_drvdata(pdev, mux);
	return 0;

err_free_pin:
	gpiod_put(pin);
err_free_mc:
	mux_control_put(mc);
err_free_mux:
	kfree(mux);
	return err;
}

static const struct of_device_id gpio_mux_input_id[] = {
	{
		.compatible = "gpio-mux-input"",
		.data = NULL,
	},
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, gpio_mux_input_id);

static struct platform_driver gpio_mux_input_driver = {
	.driver	= {
		.name		= DRIVER_NAME,
		.owner		= THIS_MODULE,
		.of_match_table = gpio_mux_input_id,
	},
	.probe	= gpio_mux_input_probe,
};
module_platform_driver(gpio_mux_input_driver);

MODULE_AUTHOR("Gabor Juhos <juhosg@openwrt.org>");
MODULE_DESCRIPTION("GPIO expander driver for NXP 74HC153");
MODULE_LICENSE("GPL v2");
MODULE_ALIAS("platform:" DRIVER_NAME);
