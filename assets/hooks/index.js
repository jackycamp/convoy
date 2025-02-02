const UseFocus = {
  mounted() {
    this.handleEvent("focus", ({ selector }) => {
      const target = this.el.querySelector(`#${selector}`);
      if (target) {
        target.focus();
      }
    });

    this.handleEvent("set_value", ({ selector, value }) => {
      const target = this.el.querySelector(`#${selector}`);
      if (target) {
        target.value = value;
      }
    });
  },
};

export default {
  UseFocus: UseFocus,
};
