"use strict";
const imageDialog = document.getElementById('image-dialog');
const imageTitle = document.getElementById('image-title');
const expandedImage = document.getElementById('expanded-image');
document.querySelectorAll('.screen-zoom').forEach(button => {
  button.addEventListener('click', () => {
    imageTitle.textContent = button.getAttribute('aria-label').replace(/を拡大$/, '');
    expandedImage.src = button.querySelector('img').src;
    expandedImage.alt = button.querySelector('img').alt;
    imageDialog.showModal();
  });
});
document.getElementById('image-close').addEventListener('click', () => imageDialog.close());
