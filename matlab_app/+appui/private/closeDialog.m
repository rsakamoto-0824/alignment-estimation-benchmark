function closeDialog(dialog)
if ~isempty(dialog) && isvalid(dialog)
    close(dialog);
end
end
