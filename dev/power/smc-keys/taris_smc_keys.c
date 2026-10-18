// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (C) 2026 George Dobreff ("Witcher") and contributors
 *
 * A read-only view of the Apple SMC's keys, for measuring power per component on TarisOS.
 * Loaded by hand on a development machine; nothing loads it on its own.
 *
 * At load it lists every SMC key with its type, size and flags. It never writes a key: SMC
 * writes control fans, charging and power. Values are read only while one of the files below is
 * being read, so the SMC coprocessor gets no extra messages while nothing reads them.
 *
 *   /sys/kernel/debug/taris-smc/keys   every key: name, type, size, flags (root)
 *   /sys/kernel/debug/taris-smc/power  every readable float key starting with P, read now (root)
 *   /sys/kernel/taris-smc/sample       the float keys named in sample=, read now (anyone)
 *
 * Usage: insmod taris_smc_keys.ko [sample=PSTR,PDTR,...]
 *        rmmod taris_smc_keys
 *
 * Don't unbind the macsmc driver while this is loaded: it keeps a pointer to that driver's data.
 */

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/ctype.h>
#include <linux/debugfs.h>
#include <linux/kobject.h>
#include <linux/mfd/macsmc.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/sysfs.h>

/* sample= is meant for a few chosen keys at a modest rate: each one is a message to the SMC */
#define SAMPLE_MAX	16

#define TYPE_FLT	__SMC_KEY('f', 'l', 't', ' ')

struct key_entry {
	smc_key key;
	u32 type;
	u8 size;
	u8 flags;
};

static char *sample = "";
module_param(sample, charp, 0444);
MODULE_PARM_DESC(sample, "Float keys for /sys/kernel/taris-smc/sample, comma-separated (e.g. PSTR,PDTR)");

static struct platform_device *smc_pdev;
static struct apple_smc *smc;
static struct key_entry *keys;
static u32 nkeys;
static u32 npower;
static const struct key_entry *sample_keys[SAMPLE_MAX];
static unsigned int nsample;
static struct dentry *dbg_dir;
static struct kobject *sysfs_dir;

static void fourcc(u32 code, char name[5])
{
	int i;

	for (i = 0; i < 4; i++) {
		char c = code >> (24 - 8 * i);

		name[i] = isprint(c) ? c : '?';
	}
	name[4] = '\0';
}

/* Only keys the SMC marks readable, and never function keys, which act when accessed */
static bool readable_flt(const struct key_entry *e)
{
	return (e->flags & APPLE_SMC_READABLE) && !(e->flags & APPLE_SMC_FUNCTION) &&
	       e->type == TYPE_FLT && e->size == 4;
}

static bool power_key(const struct key_entry *e)
{
	return (e->key >> 24) == 'P' && readable_flt(e);
}

/*
 * An IEEE 754 single as a decimal string with six places, without floating point in the kernel.
 * The conversion follows macsmc_hwmon_read_f32_scaled() in drivers/hwmon/macsmc-hwmon.c.
 */
static void flt_str(u32 fval, char *buf, size_t len)
{
	int exp = (fval >> 23) & 0xff;
	const char *sign = (fval & BIT(31)) ? "-" : "";
	u64 val;

	if (exp == 0xff) {
		if (fval & GENMASK(22, 0))
			snprintf(buf, len, "nan");
		else
			snprintf(buf, len, "%sinf", sign);
		return;
	}
	if (exp == 0) {
		/* Zero, or a subnormal far below a millionth */
		snprintf(buf, len, "%s0.000000", sign);
		return;
	}

	/* The mantissa in millionths is below 2^24 * 10^6 < 2^44, so it fits before shifting */
	val = (u64)((fval & GENMASK(22, 0)) | BIT(23)) * 1000000;
	exp -= 127 + 23;
	if (exp < 0)
		val = exp < -63 ? 0 : val >> -exp;
	else if (exp > 63 || val > (U64_MAX >> exp))
		val = U64_MAX;
	else
		val <<= exp;

	if (val == U64_MAX)
		snprintf(buf, len, "%sbig", sign);
	else
		snprintf(buf, len, "%s%llu.%06llu", sign, val / 1000000, val % 1000000);
}

static int read_flt(const struct key_entry *e, char *buf, size_t len, u32 *raw)
{
	int ret = apple_smc_read_u32(smc, e->key, raw);

	if (ret < 0)
		return ret;
	flt_str(*raw, buf, len);
	return 0;
}

static int keys_show(struct seq_file *m, void *v)
{
	char name[5], type[5];
	u32 i;

	seq_printf(m, "# %u keys: key type size flags (r readable, w writable, f function)\n",
		   nkeys);
	for (i = 0; i < nkeys; i++) {
		const struct key_entry *e = &keys[i];

		fourcc(e->key, name);
		fourcc(e->type, type);
		seq_printf(m, "%s %s %3u %c%c%c 0x%02x\n", name, type, e->size,
			   (e->flags & APPLE_SMC_READABLE) ? 'r' : '-',
			   (e->flags & APPLE_SMC_WRITABLE) ? 'w' : '-',
			   (e->flags & APPLE_SMC_FUNCTION) ? 'f' : '-', e->flags);
	}
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(keys);

static int power_show(struct seq_file *m, void *v)
{
	char name[5], val[32];
	u32 i, raw;
	int ret;

	seq_printf(m, "# %u readable float keys starting with P: key value raw\n", npower);
	for (i = 0; i < nkeys; i++) {
		const struct key_entry *e = &keys[i];

		if (!power_key(e))
			continue;
		fourcc(e->key, name);
		ret = read_flt(e, val, sizeof(val), &raw);
		if (ret < 0)
			seq_printf(m, "%s error %d\n", name, ret);
		else
			seq_printf(m, "%s %s 0x%08x\n", name, val, raw);
	}
	return 0;
}

/* Sized so seq_file never has to call power_show() twice, which would read every key again */
static int power_open(struct inode *inode, struct file *file)
{
	return single_open_size(file, power_show, NULL, 64 * (npower + 1));
}

static const struct file_operations power_fops = {
	.owner = THIS_MODULE,
	.open = power_open,
	.read = seq_read,
	.llseek = seq_lseek,
	.release = single_release,
};

static ssize_t sample_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	char name[5], val[32];
	unsigned int i;
	int len = 0;
	u32 raw;

	for (i = 0; i < nsample; i++) {
		fourcc(sample_keys[i]->key, name);
		if (read_flt(sample_keys[i], val, sizeof(val), &raw) < 0)
			len += sysfs_emit_at(buf, len, "%s error\n", name);
		else
			len += sysfs_emit_at(buf, len, "%s %s\n", name, val);
	}
	return len;
}

static struct kobj_attribute sample_attr = __ATTR_RO(sample);

static int enumerate_keys(void)
{
	struct apple_smc_key_info info;
	u32 i, failed = 0;
	smc_key key;
	int ret;

	keys = kvcalloc(smc->key_count, sizeof(*keys), GFP_KERNEL);
	if (!keys)
		return -ENOMEM;

	for (i = 0; i < smc->key_count; i++) {
		ret = apple_smc_get_key_by_index(smc, i, &key);
		if (ret < 0) {
			pr_err("can't read key %u of %u: %d\n", i, smc->key_count, ret);
			return ret;
		}
		ret = apple_smc_get_key_info(smc, key, &info);
		if (ret < 0) {
			failed++;
			continue;
		}
		keys[nkeys++] = (struct key_entry){
			.key = key, .type = info.type_code, .size = info.size, .flags = info.flags,
		};
		if (power_key(&keys[nkeys - 1]))
			npower++;
	}

	if (failed)
		pr_warn("no info for %u keys; they are left out\n", failed);
	return 0;
}

static const struct key_entry *find_key(smc_key key)
{
	u32 i;

	for (i = 0; i < nkeys; i++)
		if (keys[i].key == key)
			return &keys[i];
	return NULL;
}

static int parse_sample(void)
{
	char *list, *p, *tok;
	int ret = 0;

	list = kstrdup(sample, GFP_KERNEL);
	if (!list)
		return -ENOMEM;

	p = list;
	while ((tok = strsep(&p, ",")) != NULL) {
		const struct key_entry *e;

		if (!*tok)
			continue;
		if (strlen(tok) != 4) {
			pr_err("sample: '%s' isn't a four-character key\n", tok);
			ret = -EINVAL;
			break;
		}
		if (nsample == SAMPLE_MAX) {
			pr_err("sample: at most %d keys\n", SAMPLE_MAX);
			ret = -EINVAL;
			break;
		}
		e = find_key(__SMC_KEY(tok[0], tok[1], tok[2], tok[3]));
		if (!e || !readable_flt(e)) {
			pr_err("sample: %s isn't a readable float key\n", tok);
			ret = -EINVAL;
			break;
		}
		sample_keys[nsample++] = e;
	}

	kfree(list);
	return ret;
}

static int __init taris_smc_keys_init(void)
{
	struct device_node *np;
	int ret;

	np = of_find_compatible_node(NULL, NULL, "apple,smc");
	if (!np)
		return -ENODEV;
	smc_pdev = of_find_device_by_node(np);
	of_node_put(np);
	if (!smc_pdev)
		return -ENODEV;

	smc = platform_get_drvdata(smc_pdev);
	if (!smc_pdev->dev.driver || !smc || smc->boot_stage != APPLE_SMC_INITIALIZED) {
		pr_err("the SMC driver isn't ready\n");
		ret = -ENODEV;
		goto err_put;
	}

	ret = enumerate_keys();
	if (ret < 0)
		goto err_free;
	ret = parse_sample();
	if (ret < 0)
		goto err_free;

	sysfs_dir = kobject_create_and_add("taris-smc", kernel_kobj);
	if (!sysfs_dir) {
		ret = -ENOMEM;
		goto err_free;
	}
	ret = sysfs_create_file(sysfs_dir, &sample_attr.attr);
	if (ret < 0)
		goto err_kobj;

	dbg_dir = debugfs_create_dir("taris-smc", NULL);
	debugfs_create_file("keys", 0400, dbg_dir, NULL, &keys_fops);
	debugfs_create_file("power", 0400, dbg_dir, NULL, &power_fops);

	pr_info("%u of %u keys listed, %u power keys, %u sampled\n",
		nkeys, smc->key_count, npower, nsample);
	return 0;

err_kobj:
	kobject_put(sysfs_dir);
err_free:
	kvfree(keys);
err_put:
	put_device(&smc_pdev->dev);
	return ret;
}

static void __exit taris_smc_keys_exit(void)
{
	/* Both removals wait for reads in progress, so nothing uses the keys after this */
	debugfs_remove_recursive(dbg_dir);
	kobject_put(sysfs_dir);
	kvfree(keys);
	put_device(&smc_pdev->dev);
}

module_init(taris_smc_keys_init);
module_exit(taris_smc_keys_exit);

MODULE_AUTHOR("George Dobreff (\"Witcher\") and contributors");
MODULE_DESCRIPTION("TarisOS: read-only view of the Apple SMC's keys, for power measurement");
MODULE_LICENSE("GPL");
