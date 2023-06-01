#!/usr/bin/env python3

import os
import sys
from textwrap import dedent
import jinja2 as j2
from jinja2 import meta
import yaml
import re

from python_utils import (
    import_vars,  
    print_info_msg, 
    print_err_msg_exit,
    cfg_to_yaml_str,
    load_shell_config,
    flatten_dict,
    cp_vrfy,
    ln_vrfy,
    mkdir_vrfy,
    date_to_str
)

from fill_jinja_template import fill_jinja_template

def create_ecflow_scripts(global_var_defns_fp):
    """ Creates ecFlow job cards and definition script in the specific
    experiment directory."""

    cfg = load_shell_config(global_var_defns_fp)
    cfg = flatten_dict(cfg)
    import_vars(dictionary=cfg)

    #
    #-----------------------------------------------------------------------
    #
    # Create ecFlow job cards and definition script in the experiment directory.
    #
    #-----------------------------------------------------------------------
    #
    print_info_msg(f"""
        Creating ecFlow job cards and definition scripts in the specified 
        experiment directory (EXPTDIR):
          EXPTDIR = '{EXPTDIR}'""", verbose=VERBOSE)

    #
    #-----------------------------------------------------------------------
    #
    # Copy include directory into experiment directory.
    #
    #-----------------------------------------------------------------------
    #
    cp_vrfy("-r", os.path.join(PARMdir,"ecflow/include"), os.path.join(EXPTDIR, "ecf"))

    #
    #-----------------------------------------------------------------------
    #
    # Create job cards for tasks
    #
    #-----------------------------------------------------------------------
    #
    grp_aqm_manager = ["aqm_manager", "data_cleanup"]
    grp_forecast = ["jforecast"]
    grp_nexus = ["jnexus_emission", "jnexus_gfs_sfc", "jnexus_post_split"]
    grp_post = ["jpost"]
    grp_prep = ["jget_extrn_ics", "jget_extrn_lbcs", "jics", "jlbcs", "jmake_ics", "jmake_lbcs"]
    grp_product = ["jbias_correction_o3", "jbias_correction_pm25", "jpost_stat_o3", "jpost_stat_pm25", "jpre_post_stat"]
    grp_pts_fire_emis = ["jfire_emission", "jpoint_source"]

    tsk_grp = {"aqm_manager": grp_aqm_manager, "forecast": grp_forecast, "nexus": grp_nexus, "post": grp_post, "prep": grp_prep, "product": grp_product, "pts_fire_emis": grp_pts_fire_emis}

    task_all = grp_aqm_manager + grp_forecast + grp_nexus + grp_post + grp_prep + grp_product + grp_pts_fire_emis

    for tsk in task_all:
        print('Creating ecFlow job card for', tsk)
        #
        # Set template file path
        #
        for grp_k, grp_v in tsk_grp.items():
            if tsk in grp_v:
                ecflow_script_group = grp_k
                break

        mkdir_vrfy("-p", os.path.join(EXPTDIR, "ecf/scripts", ecflow_script_group))
        ecflow_script_fn = f"{tsk}.ecf"
        ecflow_script_tmpl_fp = os.path.join(PARMdir, "ecflow/scripts", ecflow_script_group, ecflow_script_fn)
        ecflow_script_fp = os.path.join(EXPTDIR, "ecf/scripts", ecflow_script_group, ecflow_script_fn)

        settings = {
          "exptdir": EXPTDIR,
        }
        settings_str = cfg_to_yaml_str(settings)

        # Call a python script to generate the ecFlow job card.
        args = ["-q",
                "-o", ecflow_script_fp,
                "-t", ecflow_script_tmpl_fp,
                "-u", settings_str ]

        try:
            fill_jinja_template(args)
        except:
            raise Exception(
                dedent(
                f"""Call to create the ecFlow job card for '{tsk}' failed."""
                )
            )

    #
    #-----------------------------------------------------------------------
    #
    # Create soft-link for mulitple scripts
    #
    #-----------------------------------------------------------------------
    #
    max_fcst_len = max(FCST_LEN_CYCL)+1
    for itsk in range(0, max_fcst_len):
        ecf_script_orgi = os.path.join(EXPTDIR, "ecf/scripts/post", "jpost.ecf")
        ecf_script_link_fn = f"jpost_f{itsk:03d}.ecf"
        ecf_script_link = os.path.join(EXPTDIR, "ecf/scripts/post", ecf_script_link_fn)
        ln_vrfy(f"""-fsn '{ecf_script_orgi}' '{ecf_script_link}'""")

    for itsk in range(0, NUM_SPLIT_NEXUS):
        ecf_script_orgi = os.path.join(EXPTDIR, "ecf/scripts/nexus", "jnexus_emission.ecf")
        ecf_script_link_fn = f"jnexus_emission_f{itsk:02d}.ecf"
        ecf_script_link = os.path.join(EXPTDIR, "ecf/scripts/nexus", ecf_script_link_fn)
        ln_vrfy(f"""-fsn '{ecf_script_orgi}' '{ecf_script_link}'""")

    #
    #-----------------------------------------------------------------------
    #
    # Create definition file
    #
    #-----------------------------------------------------------------------
    #
    ecflow_defn_fn = f"{NET}_cycled.def"
    ecflow_defn_tmpl_fp = os.path.join(PARMdir, "ecflow/defs", "ecf_defn_template.def")
    ecflow_defn_fp = os.path.join(EXPTDIR, "ecf/defs", ecflow_defn_fn)

    settings = {
        "model_ver": model_ver,
        "exptdir": EXPTDIR,
        "net": NET,
        "run": RUN,
        "envir": envir,
        "opsroot": OPSROOT,
    }
    settings_str = cfg_to_yaml_str(settings)

    # Call a python script to generate the ecFlow job card.
    args = ["-q",
            "-o", ecflow_defn_fp,
            "-t", ecflow_defn_tmpl_fp,
            "-u", settings_str ]

    try:
        fill_jinja_template(args)
    except:
        raise Exception(
            dedent(
            f"""Call to create the ecFlow definition file failed."""
            )
        )

    #
    #-----------------------------------------------------------------------
    #
    # Create ecFlow enviroment file
    #
    #-----------------------------------------------------------------------
    #
    ecflow_env_fn = "ecf_env.def"
    ecflow_env_tmpl_fp = os.path.join(PARMdir, "ecflow/env", "env_template.sh")
    ecflow_env_fp = os.path.join(EXPTDIR, "ecf", ecflow_env_fn)
 
    ecf_home = f"{OPSROOT}/ecflow"
    ecf_data_root = f"{OPSROOT}/ecflow/data"
    ecf_outputdir = f"{OPSROOT}/ecflow/output"
    ecf_comdir = f"{OPSROOT}/ecflow/com"
    lfs_outputdir = f"{OPSROOT}/ecflow/lsf"

    date_first = date_to_str(DATE_FIRST_CYCL, format="%Y%m%d")

    settings = {
        "ecf_home": ecf_home,
        "ecf_data_root": ecf_data_root,
        "ecf_outputdir": ecf_outputdir,
        "ecf_comdir": ecf_comdir,
        "lfs_outputdir": lfs_outputdir,
        "exptdir": EXPTDIR,
        "pdy": date_first,
    }
    settings_str = cfg_to_yaml_str(settings)

    # Call a python script to generate the ecFlow job card.
    args = ["-q",
            "-o", ecflow_env_fp,
            "-t", ecflow_env_tmpl_fp,
            "-u", settings_str ]

    try:
        fill_jinja_template(args)
    except:
        raise Exception(
            dedent(
            f"""Call to create the ecFlow job card for '{tsk}' failed."""
            )
        )


    return True


if __name__ == "__main__":
    create_ecflow_scripts(global_var_defns_fp)

